defmodule BudgeteerWeb.StatementControllerTest do
  use BudgeteerWeb.ConnCase

  import Mox

  alias Budgeteer.Statements

  import Budgeteer.LedgerFixtures, only: [account_fixture: 1]
  import Budgeteer.StatementsFixtures, only: [statement_fixture: 2]

  setup :register_and_log_in_user
  setup :verify_on_exit!

  defp create_account(%{scope: scope}) do
    %{account: account_fixture(scope)}
  end

  describe "POST /accounts/:account_id/statements" do
    setup [:create_account]

    test "with a valid file, creates a statement and redirects to the statements index", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      expect(Budgeteer.AI.ClientMock, :parse_statement, fn _bytes, "application/pdf", _category_names ->
        {:ok, %{"currency" => "EUR", "transactions" => []}}
      end)

      upload = %Plug.Upload{
        path: temp_file!("hello statement"),
        filename: "statement.pdf",
        content_type: "application/pdf"
      }

      conn = post(conn, ~p"/accounts/#{account}/statements", statement: %{"file" => upload})

      assert redirected_to(conn) == ~p"/accounts/#{account}/statements"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Statement uploaded"

      assert [statement] = Statements.list_statements(scope, account)
      assert statement.filename == "statement.pdf"
      assert statement.status == :processed
    end

    test "without a file, redirects back with an error flash", %{conn: conn, account: account} do
      conn = post(conn, ~p"/accounts/#{account}/statements", statement: %{})

      assert redirected_to(conn) == ~p"/accounts/#{account}/statements/new"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Please select a file"
    end

    test "with an unsupported file type, redirects back with an error flash", %{conn: conn, account: account} do
      upload = %Plug.Upload{path: temp_file!("hi"), filename: "statement.txt", content_type: "text/plain"}

      conn = post(conn, ~p"/accounts/#{account}/statements", statement: %{"file" => upload})

      assert redirected_to(conn) == ~p"/accounts/#{account}/statements/new"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Unsupported file type"
    end

    test "with a duplicate file for the same account, redirects back with an error flash", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      content = "duplicate bytes"
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      statement_fixture(scope, %{account: account, file_hash: file_hash})

      upload = %Plug.Upload{path: temp_file!(content), filename: "statement.pdf", content_type: "application/pdf"}

      conn = post(conn, ~p"/accounts/#{account}/statements", statement: %{"file" => upload})

      assert redirected_to(conn) == ~p"/accounts/#{account}/statements/new"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already been uploaded"
    end
  end

  defp temp_file!(contents) do
    path = Path.join(System.tmp_dir!(), "statement-controller-test-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, contents)
    path
  end
end
