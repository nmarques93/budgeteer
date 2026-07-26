defmodule Budgeteer.Ledger.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accounts" do
    field :name, :string
    field :bank_name, :string
    field :currency, :string
    field :starting_balance_cents, :integer
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(account, attrs, household_scope) do
    account
    |> cast(attrs, [:name, :bank_name, :currency, :starting_balance_cents])
    |> validate_required([:name, :bank_name, :currency, :starting_balance_cents])
    |> put_change(:household_id, household_scope.user.household_id)
  end
end
