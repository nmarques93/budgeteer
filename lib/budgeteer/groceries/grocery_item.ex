defmodule Budgeteer.Groceries.GroceryItem do
  use Ecto.Schema
  import Ecto.Changeset

  # A fixed, store-aisle-ordered list rather than a user-managed table like
  # Ledger.Category — a grocery item's category is a well-known, shared
  # taxonomy (unlike income/expense categories, which are genuinely
  # household-specific), so there's nothing for a household to configure.
  # Order here is the sort/display order used throughout — matches a
  # typical supermarket's layout (fresh sections first, shelf-stable last).
  @categories [
    "Produce",
    "Dairy & Eggs",
    "Meat & Seafood",
    "Bakery",
    "Frozen",
    "Pantry",
    "Beverages",
    "Household",
    "Other"
  ]

  def categories, do: @categories

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "grocery_items" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
    field :category, :string
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
  pre-built attrs rather than taken from raw form params. `category` is
  optional — an uncategorized item just sorts last, it isn't an error.
  """
  def changeset(grocery_item, attrs, household_scope) do
    grocery_item
    |> cast(attrs, [:name, :quantity, :unit, :category, :grocery_list_id, :added_by_id])
    |> validate_required([:name, :grocery_list_id])
    |> validate_inclusion(:category, @categories)
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
