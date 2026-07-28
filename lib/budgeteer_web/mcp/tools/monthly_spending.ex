defmodule BudgeteerWeb.MCP.Tools.MonthlySpending do
  @moduledoc "Show the household's spending and income by category for the current month, versus budget."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Budgeteer.Ledger

  schema do
    %{}
  end

  @impl true
  def execute(_params, frame) do
    totals =
      frame.assigns.scope
      |> Ledger.monthly_category_totals()
      |> Enum.map(fn row ->
        %{
          category: row.name,
          type: row.type,
          total: Budgeteer.Money.format(Decimal.to_integer(row.total_cents)),
          budget: Budgeteer.Money.format(row.budget_cents)
        }
      end)

    {:reply, Response.tool() |> Response.json(totals), frame}
  end
end
