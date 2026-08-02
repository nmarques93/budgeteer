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
        class="flex flex-wrap gap-2 items-end mt-4"
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
        <.input
          field={@item_form[:category]}
          type="select"
          label={gettext("Category")}
          options={Enum.map(GroceryItem.categories(), &{category_label(&1), &1})}
          prompt={gettext("No category")}
        />
        <.button phx-disable-with={gettext("Adding...")} variant="primary">{gettext("Add")}</.button>
      </.form>

      <div class="mt-4 space-y-4">
        <div :for={{category, items} <- @grouped_items}>
          <h3 class="text-sm font-semibold uppercase tracking-wide opacity-60 mb-1">
            {category_label(category)}
          </h3>
          <ul class="space-y-1">
            <li :for={item <- items} id={"items-#{item.id}"} class="flex items-center gap-3">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                checked={item.checked}
                phx-click="toggle_checked"
                phx-value-id={item.id}
              />
              <span class={["flex-1", item.checked && "line-through opacity-60"]}>
                {item.name}
                <span :if={item.quantity} class="opacity-70 text-sm">
                  ({item.quantity} {item.unit})
                </span>
              </span>
              <.link
                phx-click={JS.push("delete_item", value: %{id: item.id})}
                data-confirm={gettext("Are you sure?")}
              >
                <.icon name="hero-trash" class="size-4" />
              </.link>
            </li>
          </ul>
        </div>
      </div>
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
     |> assign_items()}
  end

  @impl true
  def handle_event("add_item", %{"grocery_item" => params}, socket) do
    case Groceries.create_item(socket.assigns.current_scope, socket.assigns.grocery_list, params) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> assign_items()
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
      {:ok, _item} -> {:noreply, assign_items(socket)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Groceries.get_item!(socket.assigns.current_scope, id)
    {:ok, _} = Groceries.delete_item(socket.assigns.current_scope, item)

    {:noreply, assign_items(socket)}
  end

  def handle_event("clear_checked", _params, socket) do
    {:ok, _items} =
      Groceries.delete_checked_items(socket.assigns.current_scope, socket.assigns.grocery_list)

    {:noreply, assign_items(socket)}
  end

  @impl true
  def handle_info({type, %GroceryItem{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, assign_items(socket)}
  end

  defp item_form(scope) do
    to_form(Groceries.change_item(scope, %GroceryItem{}), as: "grocery_item")
  end

  # GroceryItem.categories/0's values are the stable, stored (English)
  # strings — never translated, since they're a DB-level enum, not display
  # text. This is the display-only mapping, kept as literal gettext/1 calls
  # (not a dynamic gettext(category)) so `mix gettext.extract` can actually
  # find them.
  defp category_label(nil), do: gettext("Uncategorized")
  defp category_label("Produce"), do: gettext("Produce")
  defp category_label("Dairy & Eggs"), do: gettext("Dairy & Eggs")
  defp category_label("Meat & Seafood"), do: gettext("Meat & Seafood")
  defp category_label("Bakery"), do: gettext("Bakery")
  defp category_label("Frozen"), do: gettext("Frozen")
  defp category_label("Pantry"), do: gettext("Pantry")
  defp category_label("Beverages"), do: gettext("Beverages")
  defp category_label("Household"), do: gettext("Household")
  defp category_label("Other"), do: gettext("Other")

  # Recomputed from the database on every change rather than tracked as an
  # incremental stream delta — grouping items under category headers means
  # an insert can change which groups exist and where, not just append a
  # row, so a plain recompute is both simpler and correct here. Cheap for
  # a household grocery list's size (same reasoning already applied to
  # has_checked_items below).
  defp assign_items(socket) do
    items = Groceries.list_items(socket.assigns.current_scope, socket.assigns.grocery_list)

    socket
    |> assign(:grouped_items, group_by_category(items))
    |> assign(:has_checked_items, Enum.any?(items, & &1.checked))
  end

  # `items` is already sorted by category rank (see Groceries.list_items/2),
  # so grouping just needs to preserve that order — iterating the fixed
  # category list (plus nil, for uncategorized, last) rather than sorting
  # the grouped map's own keys.
  defp group_by_category(items) do
    by_category = Enum.group_by(items, & &1.category)

    for category <- GroceryItem.categories() ++ [nil],
        category_items = Map.get(by_category, category, []),
        category_items != [] do
      {category, category_items}
    end
  end
end
