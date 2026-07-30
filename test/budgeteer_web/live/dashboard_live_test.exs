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

  describe "category spend breakdown chart" do
    test "shows one segment per expense category, excludes income, does not render with no expense spend", %{
      conn: conn,
      scope: scope
    } do
      account = account_fixture(scope, %{starting_balance: "1000.00"})
      today = Date.utc_today()

      groceries = category_fixture(scope, %{name: "Groceries", type: :expense})
      transaction_fixture(scope, %{account_id: account.id, category_id: groceries.id, amount: "-75.00", date: today})

      salary = category_fixture(scope, %{name: "Salary", type: :income})
      transaction_fixture(scope, %{account_id: account.id, category_id: salary.id, amount: "1000.00", date: today})

      {:ok, _live, html} = live(conn, ~p"/dashboard")

      assert html =~ "category-breakdown"
      assert html =~ "Groceries"
      assert html =~ "-€75.00"
      refute html =~ ~s(data-name="Salary")
    end

    test "does not render when there is no expense spend this month", %{conn: conn, scope: scope} do
      account = account_fixture(scope, %{starting_balance: "1000.00"})
      today = Date.utc_today()

      salary = category_fixture(scope, %{name: "Salary", type: :income})
      transaction_fixture(scope, %{account_id: account.id, category_id: salary.id, amount: "1000.00", date: today})

      {:ok, _live, html} = live(conn, ~p"/dashboard")

      refute html =~ "category-breakdown"
    end

    test "folds categories beyond the 8-slot cap into a single Other segment", %{conn: conn, scope: scope} do
      account = account_fixture(scope, %{starting_balance: "1000.00"})
      today = Date.utc_today()

      # 10 expense categories, alphabetically "Cat 09"/"Cat 10" sort last and
      # should fold into "Other" — the color slot is assigned by stable
      # alphabetical order among the household's categories, not by spend.
      for n <- 1..10 do
        name = "Cat #{String.pad_leading(to_string(n), 2, "0")}"
        category = category_fixture(scope, %{name: name, type: :expense})

        transaction_fixture(scope, %{
          account_id: account.id,
          category_id: category.id,
          amount: "-10.00",
          date: today
        })
      end

      {:ok, _live, html} = live(conn, ~p"/dashboard")

      assert html =~ ~s(data-name="Cat 08")
      refute html =~ ~s(data-name="Cat 09")
      refute html =~ ~s(data-name="Cat 10")
      assert html =~ ~s(data-name="Other")
      assert html =~ "-€20.00"
    end
  end
end
