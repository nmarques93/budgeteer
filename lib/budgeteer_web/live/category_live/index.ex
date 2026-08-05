defmodule BudgeteerWeb.CategoryLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {gettext("Listing Categories")}
        <:actions>
          <.button variant="primary" navigate={~p"/categories/new"}>
            <.icon name="hero-plus" /> {gettext("New Category")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="categories"
        rows={@streams.categories}
        row_click={fn {_id, category} -> JS.navigate(~p"/categories/#{category}") end}
      >
        <:col :let={{_id, category}} label={gettext("Name")}>{category.name}</:col>
        <:col :let={{_id, category}} label={gettext("Color")}>{category.color}</:col>
        <:col :let={{_id, category}} label={gettext("Budget")}>
          <.money cents={category.budget_cents} />
        </:col>
        <:col :let={{_id, category}} label={gettext("Type")}>{category.type}</:col>
        <:action :let={{_id, category}}>
          <div class="sr-only">
            <.link navigate={~p"/categories/#{category}"}>{gettext("Show")}</.link>
          </div>
          <.link navigate={~p"/categories/#{category}/edit"}>{gettext("Edit")}</.link>
        </:action>
        <:action :let={{id, category}}>
          <.link
            :if={@current_scope.user.role == :owner}
            phx-click={JS.push("delete", value: %{id: category.id}) |> hide("##{id}")}
            data-confirm={gettext("Are you sure?")}
          >
            {gettext("Delete")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Ledger.subscribe_categories(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Listing Categories"))
     |> stream(:categories, list_categories(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = Ledger.get_category!(socket.assigns.current_scope, id)

    case Ledger.delete_category(socket.assigns.current_scope, category) do
      {:ok, _} ->
        {:noreply, stream_delete(socket, :categories, category)}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, gettext("Only the household owner can delete categories."))}
    end
  end

  @impl true
  def handle_info({type, %Budgeteer.Ledger.Category{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :categories, list_categories(socket.assigns.current_scope), reset: true)}
  end

  defp list_categories(current_scope) do
    Ledger.list_categories(current_scope)
  end
end
