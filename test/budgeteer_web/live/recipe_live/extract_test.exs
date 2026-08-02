defmodule BudgeteerWeb.RecipeLive.ExtractTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox

  alias Budgeteer.Meals

  setup :register_and_log_in_user
  setup :verify_on_exit!

  test "extracting from pasted text shows a pre-filled review form, then saves on confirm", %{
    conn: conn,
    scope: scope
  } do
    expect(Budgeteer.AI.DeepSeekClientMock, :parse_recipe, fn text ->
      assert text =~ "Tomato Soup"

      {:ok,
       %{
         "name" => "Tomato Soup",
         "notes" => "Serves 4",
         "ingredients" => [
           %{"name" => "Tomatoes", "quantity" => "6", "unit" => "units"},
           %{"name" => "Salt", "quantity" => "", "unit" => "pinch"}
         ]
       }}
    end)

    {:ok, view, _html} = live(conn, ~p"/recipes/extract")

    html =
      view
      |> form("#extract-text-form", recipe_text: %{text: "Tomato Soup recipe..."})
      |> render_submit()

    assert html =~ "Extracting the recipe..."

    html = render_async(view)
    assert html =~ "Review the extracted recipe"
    assert html =~ ~s(value="Tomato Soup")
    assert html =~ ">Serves 4</textarea>"
    assert html =~ ~s(value="Tomatoes")
    assert html =~ ~s(value="6")
    assert html =~ ~s(value="Salt")
    assert html =~ ~s(value="pinch")

    view
    |> form("#recipe-review-form")
    |> render_submit()

    assert_redirect(view)
    assert [recipe] = Meals.list_recipes(scope)
    assert recipe.name == "Tomato Soup"
    assert length(recipe.ingredients) == 2
    assert Enum.find(recipe.ingredients, &(&1.name == "Salt")).quantity == nil
  end

  test "can add and remove ingredient rows while reviewing", %{conn: conn} do
    expect(Budgeteer.AI.DeepSeekClientMock, :parse_recipe, fn _text ->
      {:ok,
       %{
         "name" => "Toast",
         "notes" => "",
         "ingredients" => [%{"name" => "Bread", "quantity" => "2", "unit" => "slices"}]
       }}
    end)

    {:ok, view, _html} = live(conn, ~p"/recipes/extract")

    view |> form("#extract-text-form", recipe_text: %{text: "Toast recipe"}) |> render_submit()
    render_async(view)

    html = view |> element("button", "Add ingredient") |> render_click()
    assert html =~ ~s(phx-value-index="1")

    html = view |> element("button[phx-value-index='1']", "Remove") |> render_click()
    refute html =~ ~s(phx-value-index="1")
  end

  test "an AI error returns to the input phase with a flash, nothing saved", %{
    conn: conn,
    scope: scope
  } do
    expect(Budgeteer.AI.DeepSeekClientMock, :parse_recipe, fn _text -> {:error, :timeout} end)

    {:ok, view, _html} = live(conn, ~p"/recipes/extract")
    view |> form("#extract-text-form", recipe_text: %{text: "some recipe"}) |> render_submit()

    html = render_async(view)
    assert html =~ "Couldn&#39;t extract a recipe"
    assert html =~ "extract-text-form"
    assert Meals.list_recipes(scope) == []
  end

  test "submitting blank text shows an error and never calls the AI client", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes/extract")

    html = view |> form("#extract-text-form", recipe_text: %{text: "   "}) |> render_submit()
    assert html =~ "Paste some recipe text first"
  end

  test "extracting from a link fetches the page, then extracts and reviews like pasted text", %{
    conn: conn,
    scope: scope
  } do
    expect(Budgeteer.RecipeUrlFetcherMock, :fetch, fn "https://example.com/tomato-soup" ->
      {:ok, "Tomato Soup. Ingredients: 6 tomatoes."}
    end)

    expect(Budgeteer.AI.DeepSeekClientMock, :parse_recipe, fn text ->
      assert text == "Tomato Soup. Ingredients: 6 tomatoes."

      {:ok,
       %{
         "name" => "Tomato Soup",
         "notes" => "",
         "ingredients" => [%{"name" => "Tomatoes", "quantity" => "6", "unit" => "units"}]
       }}
    end)

    {:ok, view, _html} = live(conn, ~p"/recipes/extract")

    html =
      view
      |> form("#extract-url-form", recipe_url: %{url: "https://example.com/tomato-soup"})
      |> render_submit()

    assert html =~ "Extracting the recipe..."

    html = render_async(view)
    assert html =~ "Review the extracted recipe"
    assert html =~ ~s(value="Tomato Soup")

    view |> form("#recipe-review-form") |> render_submit()

    assert_redirect(view)
    assert [recipe] = Meals.list_recipes(scope)
    assert recipe.name == "Tomato Soup"
  end

  test "a fetch failure returns to the input phase with a link-specific flash", %{conn: conn} do
    expect(Budgeteer.RecipeUrlFetcherMock, :fetch, fn _url -> {:error, :unsafe_host} end)

    {:ok, view, _html} = live(conn, ~p"/recipes/extract")

    view
    |> form("#extract-url-form", recipe_url: %{url: "http://localhost/recipe"})
    |> render_submit()

    html = render_async(view)
    assert html =~ "Couldn&#39;t fetch that page"
    assert html =~ "extract-url-form"
  end

  test "submitting a blank link shows an error and never calls the fetcher", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes/extract")

    html = view |> form("#extract-url-form", recipe_url: %{url: "   "}) |> render_submit()
    assert html =~ "Enter a recipe link first"
  end
end
