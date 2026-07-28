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
          <.link navigate={~p"/groceries"}>Back to lists</.link>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/groceries/#{@grocery_list}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Rename
          </.button>
        </:actions>
      </.header>

      <.form for={@item_form} id="add-item-form" phx-submit="add_item" class="flex gap-2 items-end mt-4">
        <.input field={@item_form[:name]} type="text" label="Item" placeholder="e.g. Milk" />
        <.input field={@item_form[:quantity]} type="number" step="any" label="Qty" />
        <.input field={@item_form[:unit]} type="text" label="Unit" placeholder="kg, l, units" />
        <.button phx-disable-with="Adding..." variant="primary">Add</.button>
      </.form>

      <ul id="grocery-items" phx-update="stream" class="mt-4 space-y-1">
        <li :for={{id, item} <- @streams.items} id={id} class="flex items-center gap-3">
          <input type="checkbox" class="checkbox checkbox-sm" checked={item.checked} phx-click="toggle_checked" phx-value-id={item.id} />
          <span class={["flex-1", item.checked && "line-through opacity-60"]}>
            {item.name} <span :if={item.quantity} class="opacity-70 text-sm">({item.quantity} {item.unit})</span>
          </span>
          <.link phx-click={JS.push("delete_item", value: %{id: item.id})} data-confirm="Are you sure?">
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

    {:ok,
     socket
     |> assign(:page_title, grocery_list.name)
     |> assign(:grocery_list, grocery_list)
     |> assign(:item_form, item_form(socket.assigns.current_scope))
     |> stream(:items, Groceries.list_items(socket.assigns.current_scope, grocery_list))}
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
      {:ok, item} -> {:noreply, stream_insert(socket, :items, item)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Groceries.get_item!(socket.assigns.current_scope, id)
    {:ok, _} = Groceries.delete_item(socket.assigns.current_scope, item)

    {:noreply, stream_delete(socket, :items, item)}
  end

  @impl true
  def handle_info({type, %GroceryItem{} = item}, socket) when type in [:created, :updated] do
    {:noreply, stream_insert(socket, :items, item)}
  end

  def handle_info({:deleted, %GroceryItem{} = item}, socket) do
    {:noreply, stream_delete(socket, :items, item)}
  end

  defp item_form(scope) do
    to_form(Groceries.change_item(scope, %GroceryItem{}), as: "grocery_item")
  end
end
