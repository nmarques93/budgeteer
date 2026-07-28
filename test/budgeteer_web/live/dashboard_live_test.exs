defmodule BudgeteerWeb.DashboardLiveTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.LedgerFixtures

  setup :register_and_log_in_user

  test "shows the total balance and a balance trend chart", %{conn: conn, scope: scope} do
    account_fixture(scope, %{starting_balance: "150.00"})

    {:ok, _live, html} = live(conn, ~p"/dashboard")

    assert html =~ "€150.00"
    assert html =~ "<svg"
    assert html =~ "polyline"
  end

  test "shows an over-budget meter in red and an under-budget meter in brass", %{conn: conn, scope: scope} do
    account = account_fixture(scope, %{starting_balance: "1000.00"})
    today = Date.utc_today()

    over = category_fixture(scope, %{name: "Groceries", type: :expense, budget: "50.00"})
    transaction_fixture(scope, %{account_id: account.id, category_id: over.id, amount: "-80.00", date: today})

    under = category_fixture(scope, %{name: "Transport", type: :expense, budget: "60.00"})
    transaction_fixture(scope, %{account_id: account.id, category_id: under.id, amount: "-20.00", date: today})

    {:ok, _live, html} = live(conn, ~p"/dashboard")

    assert html =~ "bg-error"
    assert html =~ "bg-primary"
  end

  test "does not render a meter for an income category or a budgetless category", %{conn: conn, scope: scope} do
    account = account_fixture(scope, %{starting_balance: "1000.00"})
    today = Date.utc_today()

    income = category_fixture(scope, %{name: "Salary", type: :income, budget: nil})
    transaction_fixture(scope, %{account_id: account.id, category_id: income.id, amount: "1000.00", date: today})

    no_budget = category_fixture(scope, %{name: "Misc", type: :expense, budget: nil})
    transaction_fixture(scope, %{account_id: account.id, category_id: no_budget.id, amount: "-5.00", date: today})

    {:ok, _live, html} = live(conn, ~p"/dashboard")

    refute html =~ "bg-error"
    refute html =~ "bg-primary"
  end
end
