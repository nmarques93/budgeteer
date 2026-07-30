defmodule Budgeteer.Ledger.Category do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "categories" do
    field :name, :string
    field :color, :string
    field :budget_cents, :integer
    field :budget, :string, virtual: true
    field :type, Ecto.Enum, values: [:income, :expense]
    field :household_id, :binary_id
    field :budget_alert_sent_for, :date

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs, household_scope) do
    category
    |> cast(attrs, [:name, :color, :budget, :type])
    |> validate_required([:name, :type])
    |> put_budget_cents()
    |> put_change(:household_id, household_scope.user.household_id)
    |> unique_constraint(:name, name: :categories_household_id_name_index)
  end

  defp put_budget_cents(changeset) do
    case get_change(changeset, :budget) do
      nil ->
        changeset

      str ->
        case Budgeteer.Money.to_cents(str) do
          :error -> add_error(changeset, :budget, "is invalid")
          cents -> put_change(changeset, :budget_cents, cents)
        end
    end
  end
end
