defmodule BudgeteerWeb.AccountLiveTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.LedgerFixtures

  @create_attrs %{name: "some name", currency: "some currency", bank_name: "some bank_name", starting_balance: "0.42"}
  @update_attrs %{name: "some updated name", currency: "some updated currency", bank_name: "some updated bank_name", starting_balance: "0.43"}
  @invalid_attrs %{name: nil, currency: nil, bank_name: nil, starting_balance: nil}

  setup :register_and_log_in_user

  defp create_account(%{scope: scope}) do
    account = account_fixture(scope)

    %{account: account}
  end

  describe "Index" do
    setup [:create_account]

    test "lists all accounts", %{conn: conn, account: account} do
      {:ok, _index_live, html} = live(conn, ~p"/accounts")

      assert html =~ "Listing Accounts"
      assert html =~ account.name
    end

    test "saves new account", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/accounts")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Account")
               |> render_click()
               |> follow_redirect(conn, ~p"/accounts/new")

      assert render(form_live) =~ "New Account"

      assert form_live
             |> form("#account-form", account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#account-form", account: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/accounts")

      html = render(index_live)
      assert html =~ "Account created successfully"
      assert html =~ "some name"
    end

    test "updates account in listing", %{conn: conn, account: account} do
      {:ok, index_live, _html} = live(conn, ~p"/accounts")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#accounts-#{account.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/accounts/#{account}/edit")

      assert render(form_live) =~ "Edit Account"

      assert form_live
             |> form("#account-form", account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#account-form", account: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/accounts")

      html = render(index_live)
      assert html =~ "Account updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes account in listing", %{conn: conn, account: account} do
      {:ok, index_live, _html} = live(conn, ~p"/accounts")

      assert index_live |> element("#accounts-#{account.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#accounts-#{account.id}")
    end
  end

  describe "Show" do
    setup [:create_account]

    test "displays account", %{conn: conn, account: account} do
      {:ok, _show_live, html} = live(conn, ~p"/accounts/#{account}")

      assert html =~ "Show Account"
      assert html =~ account.name
    end

    test "updates account and returns to show", %{conn: conn, account: account} do
      {:ok, show_live, _html} = live(conn, ~p"/accounts/#{account}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/accounts/#{account}/edit?return_to=show")

      assert render(form_live) =~ "Edit Account"

      assert form_live
             |> form("#account-form", account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#account-form", account: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/accounts/#{account}")

      html = render(show_live)
      assert html =~ "Account updated successfully"
      assert html =~ "some updated name"
    end
  end
end
