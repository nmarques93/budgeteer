defmodule BudgeteerWeb.CategoryLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Category {@category.id}
        <:subtitle>This is a category record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/categories"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/categories/#{@category}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit category
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@category.name}</:item>
        <:item title="Color">{@category.color}</:item>
        <:item title="Budget">{Budgeteer.Money.format(@category.budget_cents)}</:item>
        <:item title="Type">{@category.type}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Ledger.subscribe_categories(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Category")
     |> assign(:category, Ledger.get_category!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %Budgeteer.Ledger.Category{id: id} = category},
        %{assigns: %{category: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :category, category)}
  end

  def handle_info(
        {:deleted, %Budgeteer.Ledger.Category{id: id}},
        %{assigns: %{category: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current category was deleted.")
     |> push_navigate(to: ~p"/categories")}
  end

  def handle_info({type, %Budgeteer.Ledger.Category{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
