defmodule BudgeteerWeb.GroceryListLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Groceries
  alias Budgeteer.Groceries.GroceryItem

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {@grocery_list.name}
        <:subtitle>
          <.link navigate={~p"/groceries"}>{gettext("Back to lists")}</.link>
        </:subtitle>
        <:actions>
          <.button
            :if={@has_checked_items}
            phx-click="clear_checked"
            data-confirm={gettext("Remove every checked item?")}
          >
            <.icon name="hero-trash" /> {gettext("Clear checked")}
          </.button>
          <.button navigate={~p"/groceries/#{@grocery_list}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> {gettext("Rename")}
          </.button>
        </:actions>
      </.header>

      <.form
        for={@item_form}
        id="add-item-form"
        phx-submit="add_item"
        class="flex gap-2 items-end mt-4"
      >
        <.input
          field={@item_form[:name]}
          type="text"
          label={gettext("Item")}
          placeholder={gettext("e.g. Milk")}
        />
        <.input field={@item_form[:quantity]} type="number" step="any" label={gettext("Qty")} />
        <.input
          field={@item_form[:unit]}
          type="text"
          label={gettext("Unit")}
          placeholder={gettext("kg, l, units")}
        />
        <.button phx-disable-with={gettext("Adding...")} variant="primary">{gettext("Add")}</.button>
      </.form>

      <ul id="grocery-items" phx-update="stream" class="mt-4 space-y-1">
        <li :for={{id, item} <- @streams.items} id={id} class="flex items-center gap-3">
          <input
            type="checkbox"
            class="checkbox checkbox-sm"
            checked={item.checked}
            phx-click="toggle_checked"
            phx-value-id={item.id}
          />
          <span class={["flex-1", item.checked && "line-through opacity-60"]}>
            {item.name}
            <span :if={item.quantity} class="opacity-70 text-sm">({item.quantity} {item.unit})</span>
          </span>
          <.link
            phx-click={JS.push("delete_item", value: %{id: item.id})}
            data-confirm={gettext("Are you sure?")}
          >
            <.icon name="hero-trash" class="size-4" />
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    grocery_list = Groceries.get_grocery_list!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Groceries.subscribe_items(socket.assigns.current_scope, grocery_list)
    end

    items = Groceries.list_items(socket.assigns.current_scope, grocery_list)

    {:ok,
     socket
     |> assign(:page_title, grocery_list.name)
     |> assign(:grocery_list, grocery_list)
     |> assign(:item_form, item_form(socket.assigns.current_scope))
     |> assign(:has_checked_items, Enum.any?(items, & &1.checked))
     |> stream(:items, items)}
  end

  @impl true
  def handle_event("add_item", %{"grocery_item" => params}, socket) do
    case Groceries.create_item(socket.assigns.current_scope, socket.assigns.grocery_list, params) do
      {:ok, item} ->
        {:noreply,
         socket
         |> stream_insert(:items, item)
         |> assign(:item_form, item_form(socket.assigns.current_scope))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :item_form, to_form(changeset, as: "grocery_item"))}
    end
  end

  def handle_event("toggle_checked", %{"id" => id}, socket) do
    item = Groceries.get_item!(socket.assigns.current_scope, id)

    result =
      if item.checked do
        Groceries.uncheck_item(socket.assigns.current_scope, item)
      else
        Groceries.check_item(socket.assigns.current_scope, item)
      end

    case result do
      {:ok, item} ->
        {:noreply, socket |> stream_insert(:items, item) |> assign_has_checked_items()}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Groceries.get_item!(socket.assigns.current_scope, id)
    {:ok, _} = Groceries.delete_item(socket.assigns.current_scope, item)

    {:noreply, socket |> stream_delete(:items, item) |> assign_has_checked_items()}
  end

  def handle_event("clear_checked", _params, socket) do
    {:ok, items} =
      Groceries.delete_checked_items(socket.assigns.current_scope, socket.assigns.grocery_list)

    socket =
      items
      |> Enum.reduce(socket, &stream_delete(&2, :items, &1))
      |> assign(:has_checked_items, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({type, %GroceryItem{} = item}, socket) when type in [:created, :updated] do
    {:noreply, socket |> stream_insert(:items, item) |> assign_has_checked_items()}
  end

  def handle_info({:deleted, %GroceryItem{} = item}, socket) do
    {:noreply, socket |> stream_delete(:items, item) |> assign_has_checked_items()}
  end

  defp item_form(scope) do
    to_form(Groceries.change_item(scope, %GroceryItem{}), as: "grocery_item")
  end

  # Streams can't be queried ("has any item checked?") outside of a `for`
  # comprehension — see Phoenix.LiveView.LiveStream — so this stays a
  # plain assign, recomputed from the database on every change rather than
  # tracked as an incremental delta (simpler, and cheap for a household
  # grocery list's size).
  defp assign_has_checked_items(socket) do
    has_checked =
      socket.assigns.current_scope
      |> Groceries.list_items(socket.assigns.grocery_list)
      |> Enum.any?(& &1.checked)

    assign(socket, :has_checked_items, has_checked)
  end
end
