defmodule BudgeteerWeb.TransactionLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Transaction {@transaction.id}
        <:subtitle>For {@account.name}</:subtitle>
        <:actions>
          <.button navigate={~p"/accounts/#{@account}/transactions"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            variant="primary"
            navigate={~p"/accounts/#{@account}/transactions/#{@transaction}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit transaction
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Date">{@transaction.date}</:item>
        <:item title="Amount cents">{@transaction.amount_cents}</:item>
        <:item title="Merchant">{@transaction.merchant}</:item>
        <:item title="Description">{@transaction.description}</:item>
        <:item title="Notes">{@transaction.notes}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"account_id" => account_id, "id" => id}, _session, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, account_id)

    if connected?(socket) do
      Ledger.subscribe_transactions(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Transaction")
     |> assign(:account, account)
     |> assign(:transaction, Ledger.get_transaction!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %Budgeteer.Ledger.Transaction{id: id} = transaction},
        %{assigns: %{transaction: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :transaction, transaction)}
  end

  def handle_info(
        {:deleted, %Budgeteer.Ledger.Transaction{id: id}},
        %{assigns: %{transaction: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current transaction was deleted.")
     |> push_navigate(to: ~p"/accounts/#{socket.assigns.account}/transactions")}
  end

  def handle_info({type, %Budgeteer.Ledger.Transaction{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
