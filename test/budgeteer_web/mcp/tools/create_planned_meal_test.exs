defmodule BudgeteerWeb.MCP.Tools.CreatePlannedMealTest do
  use Budgeteer.DataCase

  import Budgeteer.HouseholdsFixtures

  alias Anubis.Server.Frame
  alias Budgeteer.Meals
  alias BudgeteerWeb.MCP.Tools.CreatePlannedMeal

  defp recipe_fixture(scope, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "Pancakes", ingredients: [%{name: "Flour"}]})
    {:ok, recipe} = Meals.create_recipe(scope, attrs)
    recipe
  end

  test "plans a meal by recipe name, case-insensitively" do
    scope = household_scope_fixture()
    recipe = recipe_fixture(scope)
    frame = Frame.new(%{scope: scope})

    params = %{recipe_name: "pancakes", date: "2026-08-01"}

    assert {:reply, response, ^frame} = CreatePlannedMeal.execute(params, frame)
    assert [%{"text" => text}] = response.content
    assert %{"recipe" => "Pancakes", "date" => "2026-08-01"} = JSON.decode!(text)

    [planned_meal] = Meals.list_planned_meals(scope)
    assert planned_meal.recipe_id == recipe.id
    assert planned_meal.date == ~D[2026-08-01]
  end

  test "returns an execution error when the recipe doesn't exist" do
    scope = household_scope_fixture()
    frame = Frame.new(%{scope: scope})

    params = %{recipe_name: "Nonexistent", date: "2026-08-01"}

    assert {:error, %Anubis.MCP.Error{} = error, ^frame} =
             CreatePlannedMeal.execute(params, frame)

    assert error.message =~ "No recipe named"
    assert Meals.list_planned_meals(scope) == []
  end

  test "returns an execution error for a malformed date" do
    scope = household_scope_fixture()
    recipe_fixture(scope)
    frame = Frame.new(%{scope: scope})

    params = %{recipe_name: "Pancakes", date: "not-a-date"}

    assert {:error, %Anubis.MCP.Error{} = error, ^frame} =
             CreatePlannedMeal.execute(params, frame)

    assert error.message =~ "ISO-8601"
  end
end
