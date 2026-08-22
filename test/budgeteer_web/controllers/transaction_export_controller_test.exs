defmodule BudgeteerWeb.TransactionExportControllerTest do
  use BudgeteerWeb.ConnCase

  import Budgeteer.LedgerFixtures

  setup :register_and_log_in_user

  describe "GET /transactions/export" do
    test "returns a CSV with a header row and one row per transaction", %{
      conn: conn,
      scope: scope
    } do
      account = account_fixture(scope, %{name: "Checking"})
      category = category_fixture(scope, %{name: "Groceries", type: :expense})

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: category.id,
        date: ~D[2026-07-15],
        amount: "-42.50",
        merchant: "Continente",
        description: "weekly shop",
        notes: "cash back included"
      })

      conn = get(conn, ~p"/transactions/export")

      assert response_content_type(conn, :csv) =~ "text/csv"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="transactions.csv")
             ]

      [header, row, ""] = String.split(conn.resp_body, "\r\n")
      assert header == "Date,Account,Amount,Merchant,Description,Category,Notes"

      assert row ==
               "2026-07-15,Checking,-42.50,Continente,weekly shop,Groceries,cash back included"
    end

    test "an uncategorized transaction exports as \"Uncategorized\"", %{conn: conn, scope: scope} do
      account = account_fixture(scope)
      transaction_fixture(scope, %{account_id: account.id, amount: "10.00"})

      conn = get(conn, ~p"/transactions/export")

      assert conn.resp_body =~ ",Uncategorized,"
    end

    test "quotes and escapes a field containing a comma or a quote", %{conn: conn, scope: scope} do
      account = account_fixture(scope)

      transaction_fixture(scope, %{
        account_id: account.id,
        amount: "5.00",
        merchant: ~s(Café "Central", Lda)
      })

      conn = get(conn, ~p"/transactions/export")

      assert conn.resp_body =~ ~s("Café ""Central"", Lda")
    end

    test "neutralizes a merchant/description/category/notes value that would execute as a spreadsheet formula",
         %{conn: conn, scope: scope} do
      account = account_fixture(scope)
      category = category_fixture(scope, %{name: "=2+2", type: :expense})

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "1.00",
        merchant: "=cmd|'/ C calc'!A1",
        description: "+SUM(A1:A9)",
        notes: "-1;@SUM(1+1)"
      })

      conn = get(conn, ~p"/transactions/export")

      assert conn.resp_body =~ "'=cmd|'/ C calc'!A1"
      assert conn.resp_body =~ "'+SUM(A1:A9)"
      assert conn.resp_body =~ "'-1;@SUM(1+1)"
      assert conn.resp_body =~ "'=2+2"
      refute conn.resp_body =~ ",=cmd"
      refute conn.resp_body =~ ",+SUM"
    end

    test "leaves an ordinary value starting with a non-formula character untouched", %{
      conn: conn,
      scope: scope
    } do
      account = account_fixture(scope)

      transaction_fixture(scope, %{account_id: account.id, amount: "1.00", merchant: "Continente"})

      conn = get(conn, ~p"/transactions/export")

      assert conn.resp_body =~ ",Continente,"
    end

    test "respects filter params, matching what's on screen", %{conn: conn, scope: scope} do
      account = account_fixture(scope)
      other_account = account_fixture(scope)

      transaction_fixture(scope, %{account_id: account.id, amount: "1.00", merchant: "Included"})

      transaction_fixture(scope, %{
        account_id: other_account.id,
        amount: "1.00",
        merchant: "Excluded"
      })

      conn = get(conn, ~p"/transactions/export?#{%{"account_id" => account.id}}")

      assert conn.resp_body =~ "Included"
      refute conn.resp_body =~ "Excluded"
    end

    test "only exports the current household's transactions", %{conn: conn, scope: scope} do
      account = account_fixture(scope)
      transaction_fixture(scope, %{account_id: account.id, amount: "1.00", merchant: "Mine"})

      other_scope = Budgeteer.HouseholdsFixtures.household_scope_fixture()
      other_account = account_fixture(other_scope)

      transaction_fixture(other_scope, %{
        account_id: other_account.id,
        amount: "1.00",
        merchant: "NotMine"
      })

      conn = get(conn, ~p"/transactions/export")

      assert conn.resp_body =~ "Mine"
      refute conn.resp_body =~ "NotMine"
    end

    test "requires authentication" do
      conn = build_conn() |> get(~p"/transactions/export")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
