defmodule Budgeteer.MealsTest do
  use Budgeteer.DataCase

  alias Budgeteer.Meals

  import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
  import Budgeteer.MealsFixtures
  import Budgeteer.GroceriesFixtures

  describe "recipes" do
    alias Budgeteer.Meals.Recipe

    @invalid_attrs %{name: nil}

    test "list_recipes/1 returns all scoped recipes" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      recipe = recipe_fixture(scope)
      other_recipe = recipe_fixture(other_scope)

      assert Meals.list_recipes(scope) == [recipe]
      assert Meals.list_recipes(other_scope) == [other_recipe]
    end

    test "get_recipe!/2 returns the recipe with given id, scoped" do
      scope = household_scope_fixture()
      recipe = recipe_fixture(scope)
      other_scope = household_scope_fixture()

      assert Meals.get_recipe!(scope, recipe.id) == recipe
      assert_raise Ecto.NoResultsError, fn -> Meals.get_recipe!(other_scope, recipe.id) end
    end

    test "create_recipe/2 with valid data creates a recipe with ingredients" do
      scope = household_scope_fixture()

      valid_attrs = %{
        name: "Soup",
        notes: "A simple soup",
        ingredients: [
          %{"name" => "Onion", "quantity" => "2", "unit" => "units"},
          %{"name" => "Carrot", "quantity" => "3", "unit" => "units"}
        ]
      }

      assert {:ok, %Recipe{} = recipe} = Meals.create_recipe(scope, valid_attrs)
      assert recipe.name == "Soup"
      assert recipe.notes == "A simple soup"
      assert recipe.household_id == scope.user.household_id
      assert [%{name: "Onion"}, %{name: "Carrot"}] = recipe.ingredients
    end

    test "create_recipe/2 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Meals.create_recipe(scope, @invalid_attrs)
    end

    test "update_recipe/3 with valid data updates the recipe" do
      scope = household_scope_fixture()
      recipe = recipe_fixture(scope)

      assert {:ok, %Recipe{} = recipe} = Meals.update_recipe(scope, recipe, %{name: "Updated name"})
      assert recipe.name == "Updated name"
    end

    test "update_recipe/3 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      recipe = recipe_fixture(scope)

      assert_raise MatchError, fn -> Meals.update_recipe(other_scope, recipe, %{}) end
    end

    test "delete_recipe/2 deletes the recipe" do
      scope = household_scope_fixture()
      recipe = recipe_fixture(scope)

      assert {:ok, %Recipe{}} = Meals.delete_recipe(scope, recipe)
      assert_raise Ecto.NoResultsError, fn -> Meals.get_recipe!(scope, recipe.id) end
    end

    test "delete_recipe/2 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      recipe = recipe_fixture(scope)

      assert_raise MatchError, fn -> Meals.delete_recipe(other_scope, recipe) end
    end

    test "change_recipe/3 returns a recipe changeset" do
      scope = household_scope_fixture()
      recipe = recipe_fixture(scope)
      assert %Ecto.Changeset{} = Meals.change_recipe(scope, recipe)
    end
  end

  describe "planned meals" do
    alias Budgeteer.Meals.PlannedMeal

    test "list_planned_meals/1 returns only upcoming, scoped, soonest first, with recipe preloaded" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      recipe = recipe_fixture(scope)
      other_recipe = recipe_fixture(other_scope)

      past = planned_meal_fixture(scope, recipe, %{date: Date.add(Date.utc_today(), -1)})
      soon = planned_meal_fixture(scope, recipe, %{date: Date.add(Date.utc_today(), 1)})
      later = planned_meal_fixture(scope, recipe, %{date: Date.add(Date.utc_today(), 2)})
      _other = planned_meal_fixture(other_scope, other_recipe)

      assert [%PlannedMeal{id: id1, recipe: %Budgeteer.Meals.Recipe{}}, %PlannedMeal{id: id2}] =
               Meals.list_planned_meals(scope)

      assert id1 == soon.id
      assert id2 == later.id
      refute Enum.any?(Meals.list_planned_meals(scope), &(&1.id == past.id))
    end

    test "create_planned_meal/2 with valid data plans a meal" do
      scope = household_scope_fixture()
      recipe = recipe_fixture(scope)

      assert {:ok, %PlannedMeal{} = planned_meal} =
               Meals.create_planned_meal(scope, %{recipe_id: recipe.id, date: Date.utc_today()})

      assert planned_meal.recipe_id == recipe.id
      assert planned_meal.household_id == scope.user.household_id
    end

    test "create_planned_meal/2 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Meals.create_planned_meal(scope, %{recipe_id: nil, date: nil})
    end

    test "delete_planned_meal/2 removes the meal from the plan" do
      scope = household_scope_fixture()
      recipe = recipe_fixture(scope)
      planned_meal = planned_meal_fixture(scope, recipe)

      assert {:ok, %PlannedMeal{}} = Meals.delete_planned_meal(scope, planned_meal)
      refute Enum.any?(Meals.list_planned_meals(scope), &(&1.id == planned_meal.id))
    end

    test "delete_planned_meal/2 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      recipe = recipe_fixture(scope)
      planned_meal = planned_meal_fixture(scope, recipe)

      assert_raise MatchError, fn -> Meals.delete_planned_meal(other_scope, planned_meal) end
    end
  end

  describe "add_ingredients_to_grocery_list/3" do
    test "adds every ingredient from every given recipe as a grocery item on the target list" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      recipe1 =
        recipe_fixture(scope, %{
          ingredients: [%{"name" => "Onion", "quantity" => "2", "unit" => "units"}]
        })

      recipe2 =
        recipe_fixture(scope, %{
          ingredients: [
            %{"name" => "Carrot", "quantity" => "3", "unit" => "units"},
            %{"name" => "Garlic"}
          ]
        })

      assert {:ok, 3} = Meals.add_ingredients_to_grocery_list(scope, [recipe1, recipe2], grocery_list)

      names = Budgeteer.Groceries.list_items(scope, grocery_list) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Carrot", "Garlic", "Onion"]
    end

    test "is scoped to the household via the grocery list it inserts into" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      recipe = recipe_fixture(scope, %{ingredients: [%{"name" => "Onion"}]})

      assert_raise MatchError, fn ->
        Meals.add_ingredients_to_grocery_list(other_scope, [recipe], grocery_list)
      end
    end
  end
end
