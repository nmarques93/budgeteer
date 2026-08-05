defmodule BudgeteerWeb.MCP.Tools.CreateRecipeTest do
  use Budgeteer.DataCase

  import Budgeteer.HouseholdsFixtures

  alias Anubis.Server.Frame
  alias Budgeteer.Households.AccessToken
  alias Budgeteer.Meals
  alias BudgeteerWeb.MCP.Tools.CreateRecipe

  test "creates a recipe with its ingredients" do
    scope = household_scope_fixture()
    frame = Frame.new(%{scope: scope, access_token: %AccessToken{scopes: ["read", "meal_write"]}})

    params = %{
      name: "Pancakes",
      notes: "Fluffy",
      ingredients: [
        %{name: "Flour", quantity: "2", unit: "cups"},
        %{name: "Eggs", quantity: 2, unit: nil}
      ]
    }

    assert {:reply, response, ^frame} = CreateRecipe.execute(params, frame)
    assert [%{"text" => text}] = response.content
    assert %{"name" => "Pancakes"} = JSON.decode!(text)

    [recipe] = Meals.list_recipes(scope)
    assert recipe.name == "Pancakes"
    assert recipe.notes == "Fluffy"
    assert [%{name: "Flour", unit: "cups"}, %{name: "Eggs"}] = recipe.ingredients
    assert Decimal.equal?(Enum.at(recipe.ingredients, 0).quantity, Decimal.new("2"))
  end

  test "returns an execution error for invalid input" do
    scope = household_scope_fixture()
    frame = Frame.new(%{scope: scope, access_token: %AccessToken{scopes: ["read", "meal_write"]}})

    params = %{name: "", notes: nil, ingredients: []}

    assert {:error, %Anubis.MCP.Error{}, ^frame} = CreateRecipe.execute(params, frame)
    assert Meals.list_recipes(scope) == []
  end

  test "rejects recipe writes without the meal_write scope" do
    scope = household_scope_fixture()
    frame = Frame.new(%{scope: scope, access_token: %AccessToken{scopes: ["read"]}})

    assert {:error, %Anubis.MCP.Error{} = error, ^frame} =
             CreateRecipe.execute(%{name: "Blocked", notes: nil, ingredients: []}, frame)

    assert error.message =~ "meal_write"
    assert Meals.list_recipes(scope) == []
  end
end
