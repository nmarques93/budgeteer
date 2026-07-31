defmodule BudgeteerWeb.RecipeLiveTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.MealsFixtures

  @invalid_attrs %{name: nil}

  setup :register_and_log_in_user

  defp create_recipe(%{scope: scope}) do
    %{recipe: recipe_fixture(scope, %{ingredients: [%{"name" => "Onion"}]})}
  end

  describe "Index" do
    setup [:create_recipe]

    test "lists recipes", %{conn: conn, recipe: recipe} do
      {:ok, _index_live, html} = live(conn, ~p"/recipes")

      assert html =~ "Recipes"
      assert html =~ recipe.name
    end

    test "deletes a recipe from the index", %{conn: conn, recipe: recipe} do
      {:ok, index_live, _html} = live(conn, ~p"/recipes")

      assert index_live |> element("#recipes-#{recipe.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#recipes-#{recipe.id}")
    end
  end

  describe "Form" do
    test "creates a recipe with multiple ingredients", %{conn: conn, scope: scope} do
      {:ok, form_live, _html} = live(conn, ~p"/recipes/new")

      assert form_live
             |> form("#recipe-form", recipe: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      # add two blank ingredient rows before they can be filled in, via the
      # real "Add ingredient" button (not a sort-param shortcut) — this is
      # the actual client interaction, not just the server-side mechanism
      form_live |> element("button", "Add ingredient") |> render_click()
      form_live |> element("button", "Add ingredient") |> render_click()

      assert {:ok, index_live, html} =
               form_live
               |> form("#recipe-form",
                 recipe: %{
                   name: "Soup",
                   ingredients: %{
                     "0" => %{"name" => "Onion", "quantity" => "2", "unit" => "units"},
                     "1" => %{"name" => "Carrot"}
                   }
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Recipe created successfully"
      assert has_element?(index_live, "td", "Soup")
      assert has_element?(index_live, "td", "2")

      assert [%{name: "Soup"} = recipe] = Budgeteer.Meals.list_recipes(scope)
      assert [%{name: "Onion"}, %{name: "Carrot"}] = recipe.ingredients
    end

    test "clicking 'Add ingredient' renders a blank row", %{conn: conn} do
      {:ok, form_live, _html} = live(conn, ~p"/recipes/new")

      html = form_live |> element("button", "Add ingredient") |> render_click()

      assert html =~ ~s(name="recipe[ingredients][0][name])
    end

    test "clicking 'Remove' drops that ingredient row", %{conn: conn, scope: scope} do
      recipe =
        recipe_fixture(scope, %{ingredients: [%{"name" => "Onion"}, %{"name" => "Garlic"}]})

      {:ok, form_live, _html} = live(conn, ~p"/recipes/#{recipe}/edit")

      html =
        form_live
        |> element("button[phx-value-index='0']", "Remove")
        |> render_click()

      refute html =~ ~s(value="Onion")
      assert html =~ ~s(value="Garlic")
    end
  end
end
