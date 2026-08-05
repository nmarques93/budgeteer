defmodule Budgeteer.StatementsTest do
  use Budgeteer.DataCase
  use Oban.Testing, repo: Budgeteer.Repo

  import Mox

  alias Budgeteer.Statements
  alias Budgeteer.Statements.Statement
  alias Budgeteer.Statements.ParseWorker

  import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
  import Budgeteer.LedgerFixtures, only: [account_fixture: 1, category_fixture: 2]
  import Budgeteer.StatementsFixtures

  setup :verify_on_exit!

  describe "statements" do
    test "list_statements/2 returns all scoped statements for the account" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      statement = statement_fixture(scope, %{account: account})
      other_account = account_fixture(scope)
      _other_statement = statement_fixture(scope, %{account: other_account})

      assert Statements.list_statements(scope, account) == [statement]
    end

    test "get_statement!/2 returns the scoped statement, raises across households" do
      scope = household_scope_fixture()
      statement = statement_fixture(scope)
      other_scope = household_scope_fixture()

      assert Statements.get_statement!(scope, statement.id) == statement

      assert_raise Ecto.NoResultsError, fn ->
        Statements.get_statement!(other_scope, statement.id)
      end
    end

    test "get_statement!/1 returns the statement with no scoping" do
      scope = household_scope_fixture()
      statement = statement_fixture(scope)

      assert Statements.get_statement!(statement.id) == statement
    end

    test "delete_statement/2 deletes the statement" do
      scope = household_scope_fixture()
      statement = statement_fixture(scope)

      assert {:ok, %Statement{}} = Statements.delete_statement(scope, statement)
      assert_raise Ecto.NoResultsError, fn -> Statements.get_statement!(scope, statement.id) end
    end
  end

  describe "inbound_email_address/1" do
    test "builds \"stmt-<token>@<configured domain>\" when INBOUND_EMAIL_DOMAIN is set" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      assert Statements.inbound_email_address(account) ==
               "stmt-#{account.inbound_email_token}@inbound.test"
    end

    # The "no domain configured" branch (returns nil) isn't covered by a
    # test here — it reads a global Application env value, and mutating
    # that from within a test is unsafe under this suite's async
    # execution (confirmed directly: doing so raced with a concurrently
    # running test and made it fail nondeterministically). The branch
    # itself is a one-line case clause, low-risk enough not to be worth
    # chasing safe test isolation for.
  end

  describe "create_statement_from_email/2" do
    test "creates the statement unscoped, with no uploaded_by_id, and enqueues parsing" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      path = write_temp_statement_file!()

      expect(Budgeteer.AI.ClientMock, :parse_statement, fn _bytes,
                                                           "application/pdf",
                                                           _category_names ->
        {:ok, %{"currency" => "EUR", "transactions" => []}}
      end)

      attrs = %{
        "filename" => "statement.pdf",
        "storage_path" => path,
        "file_hash" => "hash-#{System.unique_integer([:positive])}",
        "account_id" => account.id
      }

      assert {:ok, statement} = Statements.create_statement_from_email(account, attrs)
      assert statement.household_id == account.household_id
      assert is_nil(statement.uploaded_by_id)

      assert Statements.get_statement!(statement.id).status == :processed
    end

    test "duplicate file_hash for the same account returns an error changeset" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      _existing = statement_fixture(scope, %{account: account, file_hash: "dupe-hash"})

      attrs = %{
        "filename" => "statement.pdf",
        "storage_path" => write_temp_statement_file!(),
        "file_hash" => "dupe-hash",
        "account_id" => account.id
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Statements.create_statement_from_email(account, attrs)

      assert "has already been uploaded for this account" in errors_on(changeset).file_hash
    end

    test "rejects an account from another household" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      other_account = account_fixture(other_scope)

      attrs = %{
        filename: "statement.pdf",
        storage_path: write_temp_statement_file!(),
        file_hash: "hash-#{System.unique_integer([:positive])}",
        account_id: other_account.id
      }

      assert {:error, changeset} = Statements.create_statement(scope, attrs)
      assert %{account_id: ["does not belong to this household"]} = errors_on(changeset)
    end
  end

  describe "create_statement/2" do
    test "enqueues parsing, which — on success — leaves the statement processed with the AI output stored" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      path = write_temp_statement_file!()

      expect(Budgeteer.AI.ClientMock, :parse_statement, fn _bytes,
                                                           "application/pdf",
                                                           _category_names ->
        {:ok, %{"currency" => "EUR", "transactions" => []}}
      end)

      attrs = %{
        filename: "statement.pdf",
        storage_path: path,
        file_hash: "hash-#{System.unique_integer([:positive])}",
        account_id: account.id
      }

      assert {:ok, created} = Statements.create_statement(scope, attrs)

      statement = Statements.get_statement!(scope, created.id)
      assert statement.status == :processed
      assert statement.raw_ai_output == %{"currency" => "EUR", "transactions" => []}
    end

    test "on an AI client error, leaves the statement processing so Oban can retry (not immediately failed)" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      path = write_temp_statement_file!()

      expect(Budgeteer.AI.ClientMock, :parse_statement, fn _bytes, _media_type, _category_names ->
        {:error, {:http_error, 401, %{"error" => "invalid api key"}}}
      end)

      attrs = %{
        filename: "statement.pdf",
        storage_path: path,
        file_hash: "hash-#{System.unique_integer([:positive])}",
        account_id: account.id
      }

      assert {:ok, created} = Statements.create_statement(scope, attrs)

      # This is the first of up to 3 scheduled attempts (see ParseWorker) —
      # it stays :processing rather than jumping straight to :failed. The
      # "fails only on the final attempt" behavior is covered directly in
      # the ParseWorker tests below.
      statement = Statements.get_statement!(scope, created.id)
      assert statement.status == :processing
    end

    test "duplicate file_hash for the same account returns an error changeset" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      _existing = statement_fixture(scope, %{account: account, file_hash: "dupe-hash"})

      attrs = %{
        filename: "statement.pdf",
        storage_path: write_temp_statement_file!(),
        file_hash: "dupe-hash",
        account_id: account.id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Statements.create_statement(scope, attrs)
      assert "has already been uploaded for this account" in errors_on(changeset).file_hash
    end
  end

  describe "ParseWorker" do
    test "perform/1 marks the statement processed on success" do
      scope = household_scope_fixture()
      path = write_temp_statement_file!()
      statement = statement_fixture(scope, %{storage_path: path, filename: "statement.pdf"})

      expect(Budgeteer.AI.ClientMock, :parse_statement, fn _bytes,
                                                           "application/pdf",
                                                           _category_names ->
        {:ok, %{"currency" => "EUR", "transactions" => []}}
      end)

      assert :ok = perform_job(ParseWorker, %{"statement_id" => statement.id})

      updated = Statements.get_statement!(statement.id)
      assert updated.status == :processed
    end

    test "perform/1 passes the household's existing category names to the AI client" do
      scope = household_scope_fixture()
      category = category_fixture(scope, %{name: "Groceries"})
      path = write_temp_statement_file!()
      statement = statement_fixture(scope, %{storage_path: path, filename: "statement.pdf"})

      expect(Budgeteer.AI.ClientMock, :parse_statement, fn _bytes,
                                                           "application/pdf",
                                                           category_names ->
        assert category_names == [category.name]
        {:ok, %{"currency" => "EUR", "transactions" => []}}
      end)

      assert :ok = perform_job(ParseWorker, %{"statement_id" => statement.id})
    end

    test "perform/1 marks the statement failed only on the final attempt" do
      scope = household_scope_fixture()

      statement =
        statement_fixture(scope, %{
          storage_path: "/tmp/does-not-exist-#{System.unique_integer([:positive])}.pdf"
        })

      assert {:error, _reason} =
               perform_job(ParseWorker, %{"statement_id" => statement.id},
                 attempt: 3,
                 max_attempts: 3
               )

      updated = Statements.get_statement!(statement.id)
      assert updated.status == :failed
      assert updated.error_message =~ "enoent"
    end

    test "perform/1 leaves the statement processing (not failed) on a non-final attempt, so Oban retries" do
      scope = household_scope_fixture()

      statement =
        statement_fixture(scope, %{
          storage_path: "/tmp/does-not-exist-#{System.unique_integer([:positive])}.pdf"
        })

      assert {:error, _reason} =
               perform_job(ParseWorker, %{"statement_id" => statement.id},
                 attempt: 1,
                 max_attempts: 3
               )

      updated = Statements.get_statement!(statement.id)
      assert updated.status == :processing
    end
  end
end
