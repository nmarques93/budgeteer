defmodule Budgeteer.Ledger.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "transactions" do
    field :date, :date
    field :amount_cents, :integer
    field :amount, :string, virtual: true
    field :merchant, :string
    field :description, :string
    field :notes, :string
    field :account_id, :binary_id
    field :category_id, :binary_id
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(transaction, attrs, household_scope) do
    transaction
    |> cast(attrs, [:date, :amount, :merchant, :description, :notes, :account_id, :category_id])
    |> validate_required([:date, :amount, :account_id])
    |> put_amount_cents()
    |> put_change(:household_id, household_scope.user.household_id)
  end

  defp put_amount_cents(changeset) do
    case get_change(changeset, :amount) do
      nil ->
        changeset

      str ->
        case Budgeteer.Money.to_cents(str) do
          :error -> add_error(changeset, :amount, "is invalid")
          cents -> put_change(changeset, :amount_cents, cents)
        end
    end
  end
end
