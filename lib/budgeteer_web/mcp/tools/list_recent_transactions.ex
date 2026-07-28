defmodule BudgeteerWeb.MCP.Tools.ListRecentTransactions do
  @moduledoc "List the household's most recent transactions, across all accounts."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Budgeteer.Ledger

  schema do
    %{}
  end

  @impl true
  def execute(_params, frame) do
    scope = frame.assigns.scope
    accounts_by_id = Map.new(Ledger.list_accounts(scope), &{&1.id, &1.name})
    categories_by_id = Map.new(Ledger.list_categories(scope), &{&1.id, &1.name})

    transactions =
      scope
      |> Ledger.list_recent_transactions()
      |> Enum.map(fn transaction ->
        %{
          date: transaction.date,
          account: Map.get(accounts_by_id, transaction.account_id, "Unknown account"),
          merchant: transaction.merchant,
          amount: Budgeteer.Money.format(transaction.amount_cents),
          category: Map.get(categories_by_id, transaction.category_id, "Uncategorized")
        }
      end)

    {:reply, Response.tool() |> Response.json(transactions), frame}
  end
end
