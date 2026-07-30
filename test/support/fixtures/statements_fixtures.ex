defmodule Budgeteer.StatementsFixtures do
  @moduledoc """
  Test helpers for creating `Statement` entities. Inserts directly rather
  than through `Budgeteer.Statements.create_statement/2` so plain
  list/get/delete tests don't need to stub the AI client or enqueue Oban
  jobs — see `Budgeteer.StatementsTest` for the `create_statement/2` /
  `ParseWorker` tests that do need that.
  """

  alias Budgeteer.Repo
  alias Budgeteer.Statements.Statement

  import Budgeteer.LedgerFixtures

  @doc """
  Generate a statement, inserted directly (no Oban job enqueued).
  """
  def statement_fixture(scope, attrs \\ %{}) do
    account = Map.get(attrs, :account) || account_fixture(scope)

    attrs =
      attrs
      |> Map.delete(:account)
      |> Enum.into(%{
        filename: "statement.pdf",
        storage_path: "/tmp/statement-#{System.unique_integer([:positive])}.pdf",
        file_hash: "hash-#{System.unique_integer([:positive])}",
        account_id: account.id,
        household_id: scope.user.household_id
      })

    %Statement{}
    |> Statement.changeset(attrs, scope)
    |> Repo.insert!()
  end

  @doc """
  Writes `contents` to a real temp file, encrypted the same way
  `StatementController` encrypts a real upload, and returns its path — for
  tests that exercise `ParseWorker`, which reads (and decrypts) the file
  from disk.
  """
  def write_temp_statement_file!(contents \\ "fake pdf bytes") do
    path = Path.join(System.tmp_dir!(), "statement-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, Budgeteer.Vault.encrypt!(contents))
    path
  end
end
