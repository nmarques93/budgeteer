defmodule Budgeteer.Meals.PlannedMeal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "planned_meals" do
    field :date, :date
    field :household_id, :binary_id

    belongs_to :recipe, Budgeteer.Meals.Recipe

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(planned_meal, attrs, household_scope) do
    planned_meal
    |> cast(attrs, [:recipe_id, :date])
    |> validate_required([:recipe_id, :date])
    |> put_change(:household_id, household_scope.user.household_id)
  end
end
