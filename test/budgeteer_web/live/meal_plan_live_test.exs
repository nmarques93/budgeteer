defmodule BudgeteerWeb.MealPlanLiveTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.MealsFixtures
  import Budgeteer.GroceriesFixtures
  import Budgeteer.HouseholdsFixtures, only: [second_household_member_fixture: 1]

  alias Budgeteer.Groceries

  setup :register_and_log_in_user

  describe "Index" do
    test "lists upcoming planned meals", %{conn: conn, scope: scope} do
      recipe = recipe_fixture(scope)
      planned_meal = planned_meal_fixture(scope, recipe)

      {:ok, _index_live, html} = live(conn, ~p"/meal-plan")

      assert html =~ "Meal plan"
      assert html =~ recipe.name
      assert html =~ to_string(planned_meal.date)
    end

    test "plans a meal", %{conn: conn, scope: scope} do
      recipe = recipe_fixture(scope)
      {:ok, index_live, _html} = live(conn, ~p"/meal-plan")

      html =
        index_live
        |> form("#plan-meal-form", plan: %{recipe_id: recipe.id, date: Date.utc_today()})
        |> render_submit()

      assert html =~ recipe.name
    end

    test "deletes a planned meal", %{conn: conn, scope: scope} do
      recipe = recipe_fixture(scope)
      planned_meal = planned_meal_fixture(scope, recipe)
      {:ok, index_live, _html} = live(conn, ~p"/meal-plan")

      assert index_live
             |> element("#planned_meals-#{planned_meal.id} a[data-confirm]")
             |> render_click()

      refute has_element?(index_live, "#planned_meals-#{planned_meal.id}")
    end

    test "bulk-adds ingredients from every listed planned meal to the chosen grocery list", %{
      conn: conn,
      scope: scope
    } do
      grocery_list = grocery_list_fixture(scope)
      recipe1 = recipe_fixture(scope, %{ingredients: [%{"name" => "Onion"}]})
      recipe2 = recipe_fixture(scope, %{ingredients: [%{"name" => "Carrot"}]})
      planned_meal_fixture(scope, recipe1)
      planned_meal_fixture(scope, recipe2)

      {:ok, index_live, _html} = live(conn, ~p"/meal-plan")

      html =
        index_live
        |> form("#add-to-list-form", add_to_list: %{grocery_list_id: grocery_list.id})
        |> render_submit()

      assert html =~ "Added 2 ingredients"

      names = Groceries.list_items(scope, grocery_list) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Carrot", "Onion"]
    end

    test "reflects another household member planning a meal in real time", %{
      conn: conn,
      scope: scope
    } do
      recipe = recipe_fixture(scope)
      member = second_household_member_fixture(scope.user)

      {:ok, viewer_live, _html} = live(conn, ~p"/meal-plan")

      member_conn = log_in_user(build_conn(), member)
      {:ok, actor_live, _html} = live(member_conn, ~p"/meal-plan")

      actor_live
      |> form("#plan-meal-form", plan: %{recipe_id: recipe.id, date: Date.utc_today()})
      |> render_submit()

      assert render(viewer_live) =~ recipe.name
    end
  end
end
