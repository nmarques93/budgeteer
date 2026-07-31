defmodule BudgeteerWeb.GroceryListLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Groceries

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {if @show_archived, do: gettext("Archived grocery lists"), else: gettext("Grocery lists")}
        <:actions>
          <.button navigate={~p"/groceries?#{[archived: !@show_archived]}"}>
            {if @show_archived, do: gettext("Show active"), else: gettext("Show archived")}
          </.button>
          <.button variant="primary" navigate={~p"/groceries/new"}>
            <.icon name="hero-plus" /> {gettext("New list")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="grocery-lists"
        rows={@streams.grocery_lists}
        row_click={fn {_id, list} -> JS.navigate(~p"/groceries/#{list}") end}
      >
        <:col :let={{_id, list}} label={gettext("Name")}>{list.name}</:col>
        <:action :let={{_id, list}}>
          <.link :if={!@show_archived} phx-click={JS.push("archive", value: %{id: list.id})}>
            {gettext("Archive")}
          </.link>
          <.link :if={@show_archived} phx-click={JS.push("unarchive", value: %{id: list.id})}>
            {gettext("Unarchive")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Groceries.subscribe_grocery_lists(socket.assigns.current_scope)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    show_archived = params["archived"] == "true"

    {:noreply,
     socket
     |> assign(:page_title, gettext("Grocery lists"))
     |> assign(:show_archived, show_archived)
     |> stream(:grocery_lists, list_grocery_lists(socket.assigns.current_scope, show_archived),
       reset: true
     )}
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    list = Groceries.get_grocery_list!(socket.assigns.current_scope, id)
    {:ok, _} = Groceries.archive_grocery_list(socket.assigns.current_scope, list)

    {:noreply, stream_delete(socket, :grocery_lists, list)}
  end

  def handle_event("unarchive", %{"id" => id}, socket) do
    list = Groceries.get_grocery_list!(socket.assigns.current_scope, id)
    {:ok, _} = Groceries.unarchive_grocery_list(socket.assigns.current_scope, list)

    {:noreply, stream_delete(socket, :grocery_lists, list)}
  end

  @impl true
  def handle_info({type, %Budgeteer.Groceries.GroceryList{}}, socket)
      when type in [:created, :updated] do
    {:noreply,
     stream(
       socket,
       :grocery_lists,
       list_grocery_lists(socket.assigns.current_scope, socket.assigns.show_archived),
       reset: true
     )}
  end

  defp list_grocery_lists(current_scope, show_archived) do
    Groceries.list_grocery_lists(current_scope, archived: show_archived)
  end
end
