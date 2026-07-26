defmodule BudgeteerWeb.TransactionLiveTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.LedgerFixtures

  @create_attrs %{date: "2026-07-25", description: "some description", amount_cents: 42, merchant: "some merchant", notes: "some notes"}
  @update_attrs %{date: "2026-07-26", description: "some updated description", amount_cents: 43, merchant: "some updated merchant", notes: "some updated notes"}
  @invalid_attrs %{date: nil, description: nil, amount_cents: nil, merchant: nil, notes: nil}

  setup :register_and_log_in_user

  defp create_transaction(%{scope: scope}) do
    account = account_fixture(scope)
    transaction = transaction_fixture(scope, %{account_id: account.id})

    %{account: account, transaction: transaction}
  end

  describe "Index" do
    setup [:create_transaction]

    test "lists all transactions", %{conn: conn, account: account, transaction: transaction} do
      {:ok, _index_live, html} = live(conn, ~p"/accounts/#{account}/transactions")

      assert html =~ "Transactions for #{account.name}"
      assert html =~ transaction.merchant
    end

    test "saves new transaction", %{conn: conn, account: account} do
      {:ok, index_live, _html} = live(conn, ~p"/accounts/#{account}/transactions")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Transaction")
               |> render_click()
               |> follow_redirect(conn, ~p"/accounts/#{account}/transactions/new")

      assert render(form_live) =~ "New Transaction"

      assert form_live
             |> form("#transaction-form", transaction: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#transaction-form", transaction: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/accounts/#{account}/transactions")

      html = render(index_live)
      assert html =~ "Transaction created successfully"
      assert html =~ "some merchant"
    end

    test "updates transaction in listing", %{conn: conn, account: account, transaction: transaction} do
      {:ok, index_live, _html} = live(conn, ~p"/accounts/#{account}/transactions")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#transactions-#{transaction.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/accounts/#{account}/transactions/#{transaction}/edit")

      assert render(form_live) =~ "Edit Transaction"

      assert form_live
             |> form("#transaction-form", transaction: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#transaction-form", transaction: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/accounts/#{account}/transactions")

      html = render(index_live)
      assert html =~ "Transaction updated successfully"
      assert html =~ "some updated merchant"
    end

    test "deletes transaction in listing", %{conn: conn, account: account, transaction: transaction} do
      {:ok, index_live, _html} = live(conn, ~p"/accounts/#{account}/transactions")

      assert index_live |> element("#transactions-#{transaction.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#transactions-#{transaction.id}")
    end
  end

  describe "Show" do
    setup [:create_transaction]

    test "displays transaction", %{conn: conn, account: account, transaction: transaction} do
      {:ok, _show_live, html} = live(conn, ~p"/accounts/#{account}/transactions/#{transaction}")

      assert html =~ "Show Transaction"
      assert html =~ transaction.merchant
    end

    test "updates transaction and returns to show", %{conn: conn, account: account, transaction: transaction} do
      {:ok, show_live, _html} = live(conn, ~p"/accounts/#{account}/transactions/#{transaction}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(
                 conn,
                 ~p"/accounts/#{account}/transactions/#{transaction}/edit?return_to=show"
               )

      assert render(form_live) =~ "Edit Transaction"

      assert form_live
             |> form("#transaction-form", transaction: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#transaction-form", transaction: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/accounts/#{account}/transactions/#{transaction}")

      html = render(show_live)
      assert html =~ "Transaction updated successfully"
      assert html =~ "some updated merchant"
    end
  end
end
