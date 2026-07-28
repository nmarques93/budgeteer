defmodule BudgeteerWeb.RecipeLive.ShowTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.MealsFixtures
  import Budgeteer.GroceriesFixtures

  alias Budgeteer.Groceries

  setup :register_and_log_in_user

  describe "Show" do
    test "displays the recipe and its ingredients", %{conn: conn, scope: scope} do
      recipe =
        recipe_fixture(scope, %{
          name: "Soup",
          ingredients: [%{"name" => "Onion", "quantity" => "2", "unit" => "units"}]
        })

      {:ok, _show_live, html} = live(conn, ~p"/recipes/#{recipe}")

      assert html =~ "Soup"
      assert html =~ "Onion"
    end

    test "adds every ingredient to the chosen grocery list", %{conn: conn, scope: scope} do
      grocery_list = grocery_list_fixture(scope)

      recipe =
        recipe_fixture(scope, %{
          ingredients: [%{"name" => "Onion"}, %{"name" => "Carrot"}]
        })

      {:ok, show_live, _html} = live(conn, ~p"/recipes/#{recipe}")

      html =
        show_live
        |> form("#add-to-list-form", add_to_list: %{grocery_list_id: grocery_list.id})
        |> render_submit()

      assert html =~ "Added 2 ingredient(s)"

      names = Groceries.list_items(scope, grocery_list) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Carrot", "Onion"]
    end
  end
end
