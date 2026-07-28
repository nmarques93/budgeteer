defmodule Budgeteer.MealsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Budgeteer.Meals` context.
  """

  def recipe_fixture(scope, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "some recipe #{System.unique_integer()}"})

    {:ok, recipe} = Budgeteer.Meals.create_recipe(scope, attrs)
    recipe
  end

  def planned_meal_fixture(scope, recipe, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{recipe_id: recipe.id, date: Date.utc_today()})

    {:ok, planned_meal} = Budgeteer.Meals.create_planned_meal(scope, attrs)
    planned_meal
  end
end
