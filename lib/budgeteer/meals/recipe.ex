defmodule Budgeteer.Meals.Recipe do
  use Ecto.Schema
  import Ecto.Changeset

  alias Budgeteer.Meals.Ingredient

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipes" do
    field :name, :string
    field :notes, :string
    field :household_id, :binary_id
    field :image_path, :string

    embeds_many :ingredients, Ingredient, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recipe, attrs, household_scope) do
    recipe
    |> cast(attrs, [:name, :notes])
    |> validate_required([:name])
    |> cast_embed(:ingredients, with: &Ingredient.changeset/2)
    |> put_change(:household_id, household_scope.user.household_id)
  end
end
