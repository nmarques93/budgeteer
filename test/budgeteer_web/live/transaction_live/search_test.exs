defmodule BudgeteerWeb.TransactionLive.SearchTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.LedgerFixtures

  setup :register_and_log_in_user

  setup %{scope: scope} do
    account_a = account_fixture(scope, %{name: "Checking"})
    account_b = account_fixture(scope, %{name: "Savings"})

    transaction_a =
      transaction_fixture(scope, %{
        account_id: account_a.id,
        merchant: "Amazon",
        date: ~D[2026-07-01]
      })

    transaction_b =
      transaction_fixture(scope, %{
        account_id: account_b.id,
        merchant: "Local Bakery",
        date: ~D[2026-07-10]
      })

    %{
      account_a: account_a,
      account_b: account_b,
      transaction_a: transaction_a,
      transaction_b: transaction_b
    }
  end

  test "lists transactions across every account in the household", %{
    conn: conn,
    transaction_a: transaction_a,
    transaction_b: transaction_b
  } do
    {:ok, _search_live, html} = live(conn, ~p"/transactions")

    assert html =~ transaction_a.merchant
    assert html =~ transaction_b.merchant
  end

  test "does not show another household's transactions", %{conn: conn} do
    other_scope = Budgeteer.HouseholdsFixtures.household_scope_fixture()
    other_transaction = transaction_fixture(other_scope)

    {:ok, _search_live, html} = live(conn, ~p"/transactions")

    refute html =~ other_transaction.merchant
  end

  test "filters by account", %{
    conn: conn,
    account_a: account_a,
    transaction_a: transaction_a,
    transaction_b: transaction_b
  } do
    {:ok, search_live, _html} = live(conn, ~p"/transactions")

    html =
      search_live
      |> form("#transaction-filters", %{"account_id" => account_a.id})
      |> render_change()

    assert html =~ transaction_a.merchant
    refute html =~ transaction_b.merchant
  end

  test "filters by merchant query", %{
    conn: conn,
    transaction_a: transaction_a,
    transaction_b: transaction_b
  } do
    {:ok, search_live, _html} = live(conn, ~p"/transactions")

    html =
      search_live
      |> form("#transaction-filters", %{"query" => "Amazon"})
      |> render_change()

    assert html =~ transaction_a.merchant
    refute html =~ transaction_b.merchant
  end

  test "shows an empty state when no transactions match", %{conn: conn} do
    {:ok, search_live, _html} = live(conn, ~p"/transactions")

    html =
      search_live
      |> form("#transaction-filters", %{"query" => "nonexistent merchant"})
      |> render_change()

    assert html =~ "No transactions match these filters."
  end
end
