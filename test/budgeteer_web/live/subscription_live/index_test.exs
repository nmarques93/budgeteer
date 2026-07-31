defmodule BudgeteerWeb.SubscriptionLive.IndexTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.LedgerFixtures

  setup :register_and_log_in_user

  defp charge(scope, account, date, opts \\ []) do
    transaction_fixture(scope, %{
      account_id: account.id,
      date: date,
      amount: Keyword.get(opts, :amount, "-9.99"),
      merchant: Keyword.get(opts, :merchant, "Netflix")
    })
  end

  test "shows an empty state when nothing has been detected", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/subscriptions")
    assert html =~ "No recurring charges detected yet."
  end

  test "lists a detected subscription with its cadence and monthly estimate", %{
    conn: conn,
    scope: scope
  } do
    account = account_fixture(scope)
    charge(scope, account, ~D[2026-05-01])
    charge(scope, account, ~D[2026-06-01])
    charge(scope, account, ~D[2026-07-01])

    {:ok, _live, html} = live(conn, ~p"/subscriptions")

    assert html =~ "Netflix"
    assert html =~ "€9.99"
    assert html =~ "Monthly"
  end

  test "dismissing a subscription removes it from the active list and lists it under Dismissed",
       %{
         conn: conn,
         scope: scope
       } do
    account = account_fixture(scope)
    charge(scope, account, ~D[2026-05-01])
    charge(scope, account, ~D[2026-06-01])
    charge(scope, account, ~D[2026-07-01])

    {:ok, live, _html} = live(conn, ~p"/subscriptions")

    html =
      live
      |> element("a", "Dismiss")
      |> render_click()

    assert html =~ "No recurring charges detected yet."
    assert html =~ "Dismissed (1)"
    assert html =~ "netflix"
  end

  test "restoring a dismissed subscription makes it active again", %{conn: conn, scope: scope} do
    account = account_fixture(scope)
    charge(scope, account, ~D[2026-05-01])
    charge(scope, account, ~D[2026-06-01])
    charge(scope, account, ~D[2026-07-01])

    {:ok, live, _html} = live(conn, ~p"/subscriptions")
    live |> element("a", "Dismiss") |> render_click()

    html =
      live
      |> element("a", "Restore")
      |> render_click()

    assert html =~ "Netflix"
    refute html =~ "Dismissed ("
  end
end
