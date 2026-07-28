defmodule Budgeteer.Groceries.GroceryItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "grocery_items" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
    field :checked, :boolean, default: false
    field :grocery_list_id, :binary_id
    field :added_by_id, :binary_id
    field :checked_by_id, :binary_id
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for adding an item to a list. `grocery_list_id`/`added_by_id`
  are set by the context (never user-typed), so they're cast from
  pre-built attrs rather than taken from raw form params.
  """
  def changeset(grocery_item, attrs, household_scope) do
    grocery_item
    |> cast(attrs, [:name, :quantity, :unit, :grocery_list_id, :added_by_id])
    |> validate_required([:name, :grocery_list_id])
    |> put_change(:household_id, household_scope.user.household_id)
  end

  @doc """
  Changeset for the check/uncheck writes made by `Groceries.check_item/2`
  and `Groceries.uncheck_item/2` — not user input, no form ceremony needed.
  """
  def checked_changeset(grocery_item, attrs) do
    cast(grocery_item, attrs, [:checked, :checked_by_id])
  end
end
