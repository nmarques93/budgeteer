defmodule BudgeteerWeb.StatementLive.IndexTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox

  alias Budgeteer.Statements

  import Budgeteer.LedgerFixtures, only: [account_fixture: 1]
  import Budgeteer.StatementsFixtures

  setup :register_and_log_in_user
  setup :verify_on_exit!

  defp create_account(%{scope: scope}) do
    %{account: account_fixture(scope)}
  end

  describe "Index" do
    setup [:create_account]

    test "lists statements scoped to the account", %{conn: conn, scope: scope, account: account} do
      statement = statement_fixture(scope, %{account: account, filename: "visible.pdf"})
      other_account = account_fixture(scope)

      other_statement =
        statement_fixture(scope, %{account: other_account, filename: "hidden.pdf"})

      {:ok, _index_live, html} = live(conn, ~p"/accounts/#{account}/statements")

      assert html =~ "Statements for #{account.name}"
      assert html =~ statement.filename
      refute html =~ other_statement.filename
    end

    test "live-updates when a statement is uploaded and processed elsewhere", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      {:ok, index_live, html} = live(conn, ~p"/accounts/#{account}/statements")
      refute html =~ "new-statement.pdf"

      expect(Budgeteer.AI.ClientMock, :parse_statement, fn _bytes,
                                                           "application/pdf",
                                                           _category_names ->
        {:ok, %{"currency" => "EUR", "transactions" => []}}
      end)

      attrs = %{
        filename: "new-statement.pdf",
        storage_path: write_temp_statement_file!(),
        file_hash: "hash-#{System.unique_integer([:positive])}",
        account_id: account.id
      }

      assert {:ok, _created} = Statements.create_statement(scope, attrs)

      html = render(index_live)
      assert html =~ "new-statement.pdf"
      assert html =~ "Processed"
    end
  end
end
