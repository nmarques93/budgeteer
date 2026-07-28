defmodule BudgeteerWeb.TransactionLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Transactions for {@account.name}
        <:subtitle>
          <.link navigate={~p"/accounts/#{@account}"}>Back to account</.link>
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/accounts/#{@account}/transactions/new"}>
            <.icon name="hero-plus" /> New Transaction
          </.button>
        </:actions>
      </.header>

      <.table
        id="transactions"
        rows={@streams.transactions}
        row_click={
          fn {_id, transaction} -> JS.navigate(~p"/accounts/#{@account}/transactions/#{transaction}") end
        }
      >
        <:col :let={{_id, transaction}} label="Date">{transaction.date}</:col>
        <:col :let={{_id, transaction}} label="Amount"><.money cents={transaction.amount_cents} /></:col>
        <:col :let={{_id, transaction}} label="Merchant">{transaction.merchant}</:col>
        <:col :let={{_id, transaction}} label="Description">{transaction.description}</:col>
        <:col :let={{_id, transaction}} label="Notes">{transaction.notes}</:col>
        <:col :let={{_id, transaction}} label="Category">{category_name(@categories_by_id, transaction.category_id)}</:col>
        <:action :let={{_id, transaction}}>
          <div class="sr-only">
            <.link navigate={~p"/accounts/#{@account}/transactions/#{transaction}"}>Show</.link>
          </div>
          <.link navigate={~p"/accounts/#{@account}/transactions/#{transaction}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, transaction}}>
          <.link
            phx-click={JS.push("delete", value: %{id: transaction.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"account_id" => account_id}, _session, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, account_id)

    if connected?(socket) do
      Ledger.subscribe_transactions(socket.assigns.current_scope)
    end

    categories_by_id = Map.new(Ledger.list_categories(socket.assigns.current_scope), &{&1.id, &1.name})

    {:ok,
     socket
     |> assign(:page_title, "Transactions for #{account.name}")
     |> assign(:account, account)
     |> assign(:categories_by_id, categories_by_id)
     |> stream(:transactions, list_transactions(socket.assigns.current_scope, account))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    transaction = Ledger.get_transaction!(socket.assigns.current_scope, id)
    {:ok, _} = Ledger.delete_transaction(socket.assigns.current_scope, transaction)

    {:noreply, stream_delete(socket, :transactions, transaction)}
  end

  @impl true
  def handle_info({type, %Budgeteer.Ledger.Transaction{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :transactions, list_transactions(socket.assigns.current_scope, socket.assigns.account),
       reset: true
     )}
  end

  defp list_transactions(current_scope, account) do
    Ledger.list_account_transactions(current_scope, account)
  end

  defp category_name(_categories_by_id, nil), do: "Uncategorized"
  defp category_name(categories_by_id, category_id), do: Map.get(categories_by_id, category_id, "Uncategorized")
end
