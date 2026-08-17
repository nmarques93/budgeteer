defmodule Budgeteer.Statements.Statement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "statements" do
    field :filename, :string
    field :storage_path, :string
    field :file_hash, :string

    field :status, Ecto.Enum,
      values: [:pending, :processing, :processed, :failed],
      default: :pending

    field :raw_ai_output, Budgeteer.Encrypted.Map
    field :error_message, :string
    field :account_id, :binary_id
    field :uploaded_by_id, :binary_id
    field :household_id, :binary_id
    field :statement_period_start, :date
    field :statement_period_end, :date
    field :opening_balance_cents, :integer
    field :closing_balance_cents, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a statement from an uploaded file. Only fields the
  app itself sets at upload time — never user-typed form input.
  """
  def changeset(statement, attrs, household_scope) do
    statement
    |> cast(attrs, [:filename, :storage_path, :file_hash, :account_id])
    |> validate_required([:filename, :storage_path, :file_hash, :account_id])
    |> put_change(:uploaded_by_id, household_scope.user.id)
    |> put_change(:household_id, household_scope.user.household_id)
    |> unique_constraint(:file_hash,
      name: :statements_account_id_file_hash_index,
      message: "has already been uploaded for this account"
    )
  end

  @doc """
  Changeset for creating a statement from an inbound email attachment —
  same required fields as `changeset/3`, but takes `household_id`
  directly rather than a `Scope`, since there's no authenticated user to
  scope from (the webhook that calls this runs outside a request/user
  context; `uploaded_by_id` is left nil, same as any other
  non-human-triggered write in this app).
  """
  def email_changeset(statement, attrs, household_id) do
    statement
    |> cast(attrs, [:filename, :storage_path, :file_hash, :account_id])
    |> validate_required([:filename, :storage_path, :file_hash, :account_id])
    |> put_change(:household_id, household_id)
    |> unique_constraint(:file_hash,
      name: :statements_account_id_file_hash_index,
      message: "has already been uploaded for this account"
    )
  end

  @doc """
  Changeset for the status-transition writes made by the Oban worker
  (processing/processed/failed) — not user input, no form ceremony needed.
  """
  def status_changeset(statement, attrs) do
    cast(statement, attrs, [
      :status,
      :raw_ai_output,
      :error_message,
      :statement_period_start,
      :statement_period_end,
      :opening_balance_cents,
      :closing_balance_cents
    ])
  end

  def reconciliation_metadata(%{"statement_period" => period} = output) when is_map(period) do
    %{
      "statement_period_start" => parse_date(period["from"]),
      "statement_period_end" => parse_date(period["to"]),
      "opening_balance_cents" => output["opening_balance_cents"],
      "closing_balance_cents" => output["closing_balance_cents"]
    }
  end

  def reconciliation_metadata(output) when is_map(output) do
    %{
      "statement_period_start" => nil,
      "statement_period_end" => nil,
      "opening_balance_cents" => output["opening_balance_cents"],
      "closing_balance_cents" => output["closing_balance_cents"]
    }
  end

  defp parse_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_date(_date), do: nil
end
