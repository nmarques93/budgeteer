defmodule BudgeteerWeb.DashboardLive do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Dashboard
      </.header>

      <div class="mt-4">
        <div class="text-sm opacity-70">Total balance</div>
        <div class="text-3xl font-bold">{Budgeteer.Money.format(@total_balance_cents)}</div>
      </div>

      <h2 class="text-lg font-semibold mt-8">This month by category</h2>
      <.table id="category-totals" rows={@category_totals}>
        <:col :let={row} label="Category">{row.name}</:col>
        <:col :let={row} label="Type">{row.type}</:col>
        <:col :let={row} label="Spent">{Budgeteer.Money.format(row.total_cents)}</:col>
        <:col :let={row} label="Budget">{Budgeteer.Money.format(row.budget_cents)}</:col>
      </.table>

      <h2 class="text-lg font-semibold mt-8">Recent transactions</h2>
      <.table id="recent-transactions" rows={@recent_transactions}>
        <:col :let={transaction} label="Date">{transaction.date}</:col>
        <:col :let={transaction} label="Account">{account_name(@accounts_by_id, transaction.account_id)}</:col>
        <:col :let={transaction} label="Merchant">{transaction.merchant}</:col>
        <:col :let={transaction} label="Amount">{Budgeteer.Money.format(transaction.amount_cents)}</:col>
        <:col :let={transaction} label="Category">{category_name(@categories_by_id, transaction.category_id)}</:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Ledger.subscribe_accounts(scope)
      Ledger.subscribe_transactions(scope)
      Ledger.subscribe_categories(scope)
    end

    accounts_by_id = Map.new(Ledger.list_accounts(scope), &{&1.id, &1.name})
    categories_by_id = Map.new(Ledger.list_categories(scope), &{&1.id, &1.name})

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:accounts_by_id, accounts_by_id)
     |> assign(:categories_by_id, categories_by_id)
     |> load_data()}
  end

  @impl true
  def handle_info({type, _record}, socket) when type in [:created, :updated, :deleted] do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(:accounts_by_id, Map.new(Ledger.list_accounts(scope), &{&1.id, &1.name}))
     |> assign(:categories_by_id, Map.new(Ledger.list_categories(scope), &{&1.id, &1.name}))
     |> load_data()}
  end

  defp load_data(socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:total_balance_cents, Ledger.total_balance_cents(scope))
    |> assign(:category_totals, decimal_totals(Ledger.monthly_category_totals(scope)))
    |> assign(:recent_transactions, Ledger.list_recent_transactions(scope))
  end

  defp decimal_totals(rows) do
    Enum.map(rows, &Map.update!(&1, :total_cents, fn d -> Decimal.to_integer(d) end))
  end

  defp account_name(accounts_by_id, account_id), do: Map.get(accounts_by_id, account_id, "Unknown account")

  defp category_name(_categories_by_id, nil), do: "Uncategorized"
  defp category_name(categories_by_id, category_id), do: Map.get(categories_by_id, category_id, "Uncategorized")
end
