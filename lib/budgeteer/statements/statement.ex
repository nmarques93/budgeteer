defmodule Budgeteer.Statements.Statement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "statements" do
    field :filename, :string
    field :storage_path, :string
    field :file_hash, :string
    field :status, Ecto.Enum, values: [:pending, :processing, :processed, :failed], default: :pending
    field :raw_ai_output, Budgeteer.Encrypted.Map
    field :error_message, :string
    field :account_id, :binary_id
    field :uploaded_by_id, :binary_id
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a statement from an uploaded file. Only fields the
  app itself sets at upload time — never user-typed form input.
  """
  def changeset(statement, attrs, household_scope) do
    statement
    |> cast(attrs, [:filename, :storage_path, :file_hash, :account_id, :uploaded_by_id])
    |> validate_required([:filename, :storage_path, :file_hash, :account_id])
    |> put_change(:household_id, household_scope.user.household_id)
    |> unique_constraint(:file_hash, name: :statements_account_id_file_hash_index, message: "has already been uploaded for this account")
  end

  @doc """
  Changeset for the status-transition writes made by the Oban worker
  (processing/processed/failed) — not user input, no form ceremony needed.
  """
  def status_changeset(statement, attrs) do
    cast(statement, attrs, [:status, :raw_ai_output, :error_message])
  end
end
