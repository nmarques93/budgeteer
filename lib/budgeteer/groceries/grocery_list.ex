defmodule Budgeteer.Groceries.GroceryList do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "grocery_lists" do
    field :name, :string
    field :archived_at, :utc_datetime
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(grocery_list, attrs, household_scope) do
    grocery_list
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> put_change(:household_id, household_scope.user.household_id)
  end
end
