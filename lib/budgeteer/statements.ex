defmodule Budgeteer.Statements do
  @moduledoc """
  The Statements context — uploaded bank statements and their AI-parsing
  lifecycle. The Oban worker (`Budgeteer.Statements.ParseWorker`) writes
  `raw_ai_output` and flips `status`; it never creates `Transaction` records
  itself — that only happens when the user confirms extracted rows on the
  review screen (see `BudgeteerWeb.StatementLive.Review`).
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo

  alias Budgeteer.Statements.Statement
  alias Budgeteer.Statements.ParseWorker
  alias Budgeteer.Ledger.Account
  alias Budgeteer.Households.Scope

  @doc """
  Subscribes to scoped notifications about any statement changes.

  The broadcasted messages match the pattern:

    * {:created, %Statement{}}
    * {:updated, %Statement{}}
    * {:deleted, %Statement{}}

  """
  def subscribe_statements(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{scope.user.household_id}:statements")
  end

  defp broadcast_statement(household_id, message) do
    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{household_id}:statements", message)
  end

  @doc """
  Returns the list of statements for a given account.
  """
  def list_statements(%Scope{} = scope, %Account{} = account) do
    true = account.household_id == scope.user.household_id

    Repo.all_by(Statement, account_id: account.id, household_id: scope.user.household_id)
  end

  @doc """
  Gets a single statement, scoped to the household.

  Raises `Ecto.NoResultsError` if the Statement does not exist.
  """
  def get_statement!(%Scope{} = scope, id) do
    Repo.get_by!(Statement, id: id, household_id: scope.user.household_id)
  end

  @doc """
  Gets a single statement with no scoping. For use by the Oban worker,
  which runs outside a request/user context.
  """
  def get_statement!(id), do: Repo.get!(Statement, id)

  @doc """
  Creates a statement from an uploaded file and enqueues the Oban job that
  parses it. Callers don't need to know about Oban.
  """
  def create_statement(%Scope{} = scope, attrs) do
    with {:ok, statement = %Statement{}} <-
           %Statement{}
           |> Statement.changeset(attrs, scope)
           |> Repo.insert(),
         {:ok, _job} <-
           %{"statement_id" => statement.id}
           |> ParseWorker.new()
           |> Oban.insert() do
      broadcast_statement(statement.household_id, {:created, statement})
      {:ok, statement}
    end
  end

  @doc """
  Deletes a statement.
  """
  def delete_statement(%Scope{} = scope, %Statement{} = statement) do
    true = statement.household_id == scope.user.household_id

    with {:ok, statement = %Statement{}} <- Repo.delete(statement) do
      broadcast_statement(scope.user.household_id, {:deleted, statement})
      {:ok, statement}
    end
  end

  @doc """
  Marks a statement as processing. Unscoped — called by the Oban worker.
  """
  def mark_processing(%Statement{} = statement) do
    update_status(statement, %{"status" => "processing"})
  end

  @doc """
  Marks a statement as processed and stores the parsed AI output. Unscoped —
  called by the Oban worker.
  """
  def mark_processed(%Statement{} = statement, raw_ai_output) when is_map(raw_ai_output) do
    update_status(statement, %{"status" => "processed", "raw_ai_output" => raw_ai_output})
  end

  @doc """
  Marks a statement as failed with an error message. Unscoped — called by
  the Oban worker.
  """
  def mark_failed(%Statement{} = statement, error_message) when is_binary(error_message) do
    update_status(statement, %{"status" => "failed", "error_message" => error_message})
  end

  @doc """
  Clears the raw AI output once a statement's rows have been reviewed and
  confirmed into real `Transaction` records. `raw_ai_output` is a temporary
  staging artifact (see moduledoc) — keeping an indefinite encrypted copy
  of every past statement's contents around serves no purpose once it's
  been reviewed, and only widens what a future key compromise would
  expose. Scoped, since this is called from the review screen, not the
  Oban worker.
  """
  def clear_reviewed(%Scope{} = scope, %Statement{} = statement) do
    true = statement.household_id == scope.user.household_id

    update_status(statement, %{"raw_ai_output" => nil})
  end

  defp update_status(%Statement{} = statement, attrs) do
    with {:ok, statement = %Statement{}} <-
           statement
           |> Statement.status_changeset(attrs)
           |> Repo.update() do
      broadcast_statement(statement.household_id, {:updated, statement})
      {:ok, statement}
    end
  end
end
