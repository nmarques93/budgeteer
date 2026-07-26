defmodule Budgeteer.Ledger.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "transactions" do
    field :date, :date
    field :amount_cents, :integer
    field :merchant, :string
    field :description, :string
    field :notes, :string
    field :account_id, :binary_id
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(transaction, attrs, household_scope) do
    transaction
    |> cast(attrs, [:date, :amount_cents, :merchant, :description, :notes, :account_id])
    |> validate_required([:date, :amount_cents, :account_id])
    |> put_change(:household_id, household_scope.user.household_id)
  end
end
