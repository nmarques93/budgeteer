defmodule BudgeteerWeb.DashboardLiveTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox
  import Budgeteer.LedgerFixtures

  setup :register_and_log_in_user
  setup :verify_on_exit!

  describe "budget insights" do
    test "shows a Generate button with no insights yet, then the generated list", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Generate insights"

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn _data ->
        {:ok, ["You're pacing over your usual Groceries spend this month."]}
      end)

      html = view |> element("button", "Generate insights") |> render_click()
      assert html =~ "Thinking..." or html =~ "loading-spinner"

      html = render_async(view)
      assert html =~ "You&#39;re pacing over your usual Groceries spend this month."
      assert html =~ "Refresh"
    end

    test "shows a flash and clears the loading state when the client errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn _data ->
        {:error, :timeout}
      end)

      view |> element("button", "Generate insights") |> render_click()
      html = render_async(view)

      assert html =~ "Couldn&#39;t generate insights"
      refute html =~ "loading-spinner"
    end

    test "an existing empty insights list shows a friendly message, not a blank card", %{
      conn: conn,
      scope: scope
    } do
      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn _data -> {:ok, []} end)
      {:ok, _} = Budgeteer.Insights.generate_insights(scope)

      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Nothing notable stood out"
    end

    test "reflects another household member generating insights in real time", %{
      conn: conn,
      scope: scope
    } do
      {:ok, viewer_live, _html} = live(conn, ~p"/dashboard")

      member = Budgeteer.HouseholdsFixtures.second_household_member_fixture(scope.user)
      member_conn = log_in_user(build_conn(), member)
      {:ok, actor_live, _html} = live(member_conn, ~p"/dashboard")

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn _data ->
        {:ok, ["Shared household insight."]}
      end)

      actor_live |> element("button", "Generate insights") |> render_click()
      render_async(actor_live)

      assert render(viewer_live) =~ "Shared household insight."
    end
  end

  test "shows the total balance and a balance trend chart", %{conn: conn, scope: scope} do
    account_fixture(scope, %{starting_balance: "150.00"})

    {:ok, _live, html} = live(conn, ~p"/dashboard")

    assert html =~ "€150.00"
    assert html =~ "<svg"
    assert html =~ "polyline"
  end

  test "renders the (client-side gated, hidden by default) iOS install-nudge banner",
       %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/dashboard")

    assert html =~ "id=\"ios-install-banner\""
  end

  test "shows a recurring-charges card once a subscription is detected, not before", %{
    conn: conn,
    scope: scope
  } do
    account = account_fixture(scope, %{starting_balance: "1000.00"})

    {:ok, _live, html} = live(conn, ~p"/dashboard")
    refute html =~ "Recurring charges detected"

    for date <- [~D[2026-05-01], ~D[2026-06-01], ~D[2026-07-01]] do
      transaction_fixture(scope, %{
        account_id: account.id,
        date: date,
        amount: "-9.99",
        merchant: "Netflix"
      })
    end

    {:ok, _live, html} = live(conn, ~p"/dashboard")
    assert html =~ "Recurring charges detected"
    assert html =~ "1 ·"
  end

  test "shows an over-budget meter in red and an under-budget meter in brass", %{
    conn: conn,
    scope: scope
  } do
    account = account_fixture(scope, %{starting_balance: "1000.00"})
    today = Date.utc_today()

    over = category_fixture(scope, %{name: "Groceries", type: :expense, budget: "50.00"})

    transaction_fixture(scope, %{
      account_id: account.id,
      category_id: over.id,
      amount: "-80.00",
      date: today
    })

    under = category_fixture(scope, %{name: "Transport", type: :expense, budget: "60.00"})

    transaction_fixture(scope, %{
      account_id: account.id,
      category_id: under.id,
      amount: "-20.00",
      date: today
    })

    {:ok, _live, html} = live(conn, ~p"/dashboard")

    assert html =~ "bg-error"
    assert html =~ "bg-primary"
  end

  test "does not render a meter for an income category or a budgetless category", %{
    conn: conn,
    scope: scope
  } do
    account = account_fixture(scope, %{starting_balance: "1000.00"})
    today = Date.utc_today()

    income = category_fixture(scope, %{name: "Salary", type: :income, budget: nil})

    transaction_fixture(scope, %{
      account_id: account.id,
      category_id: income.id,
      amount: "1000.00",
      date: today
    })

    no_budget = category_fixture(scope, %{name: "Misc", type: :expense, budget: nil})

    transaction_fixture(scope, %{
      account_id: account.id,
      category_id: no_budget.id,
      amount: "-5.00",
      date: today
    })

    {:ok, _live, html} = live(conn, ~p"/dashboard")

    refute html =~ "bg-error"
    refute html =~ "bg-primary"
  end

  describe "category spend breakdown chart" do
    test "shows one segment per expense category, excludes income, does not render with no expense spend",
         %{
           conn: conn,
           scope: scope
         } do
      account = account_fixture(scope, %{starting_balance: "1000.00"})
      today = Date.utc_today()

      groceries = category_fixture(scope, %{name: "Groceries", type: :expense})

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: groceries.id,
        amount: "-75.00",
        date: today
      })

      salary = category_fixture(scope, %{name: "Salary", type: :income})

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: salary.id,
        amount: "1000.00",
        date: today
      })

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

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: salary.id,
        amount: "1000.00",
        date: today
      })

      {:ok, _live, html} = live(conn, ~p"/dashboard")

      refute html =~ "category-breakdown"
    end

    test "folds categories beyond the 8-slot cap into a single Other segment", %{
      conn: conn,
      scope: scope
    } do
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
