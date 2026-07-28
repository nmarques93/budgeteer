defmodule Budgeteer.Meals.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
  end

  @doc false
  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name, :quantity, :unit])
    |> validate_required([:name])
  end
end
