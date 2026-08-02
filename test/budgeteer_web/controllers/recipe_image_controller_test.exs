defmodule BudgeteerWeb.RecipeImageControllerTest do
  use BudgeteerWeb.ConnCase

  alias Budgeteer.Meals

  import Budgeteer.MealsFixtures, only: [recipe_fixture: 1]

  setup :register_and_log_in_user

  defp create_recipe(%{scope: scope}) do
    %{recipe: recipe_fixture(scope)}
  end

  describe "POST /recipes/:id/image" do
    setup [:create_recipe]

    test "with a valid image, sets the recipe's image and redirects to the recipe", %{
      conn: conn,
      scope: scope,
      recipe: recipe
    } do
      upload = %Plug.Upload{
        path: temp_png!("hello"),
        filename: "photo.png",
        content_type: "image/png"
      }

      conn = post(conn, ~p"/recipes/#{recipe}/image", image: upload)

      assert redirected_to(conn) == ~p"/recipes/#{recipe}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Image uploaded"

      recipe = Meals.get_recipe!(scope, recipe.id)
      assert recipe.image_path
      assert File.exists?(recipe.image_path)

      File.rm(recipe.image_path)
    end

    test "without an image, redirects back with an error flash", %{conn: conn, recipe: recipe} do
      conn = post(conn, ~p"/recipes/#{recipe}/image", %{})

      assert redirected_to(conn) == ~p"/recipes/#{recipe}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Please select an image"
    end

    test "with an unsupported file type, redirects back with an error flash", %{
      conn: conn,
      recipe: recipe
    } do
      path = Path.join(System.tmp_dir!(), "bad-#{System.unique_integer()}.txt")
      File.write!(path, "not an image")

      upload = %Plug.Upload{path: path, filename: "notes.txt", content_type: "text/plain"}

      conn = post(conn, ~p"/recipes/#{recipe}/image", image: upload)

      assert redirected_to(conn) == ~p"/recipes/#{recipe}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Unsupported file type"
    end

    test "with content that doesn't match its extension, redirects back with an error flash", %{
      conn: conn,
      recipe: recipe
    } do
      path = Path.join(System.tmp_dir!(), "spoofed-#{System.unique_integer()}.png")
      File.write!(path, "not actually a png")

      upload = %Plug.Upload{path: path, filename: "photo.png", content_type: "image/png"}

      conn = post(conn, ~p"/recipes/#{recipe}/image", image: upload)

      assert redirected_to(conn) == ~p"/recipes/#{recipe}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "doesn't match its extension"
    end

    test "belongs to another household, raises", %{conn: conn} do
      other_recipe = recipe_fixture(Budgeteer.HouseholdsFixtures.household_scope_fixture())

      upload = %Plug.Upload{
        path: temp_png!("hello"),
        filename: "photo.png",
        content_type: "image/png"
      }

      assert_raise Ecto.NoResultsError, fn ->
        post(conn, ~p"/recipes/#{other_recipe}/image", image: upload)
      end
    end
  end

  describe "GET /recipes/:id/image" do
    setup [:create_recipe]

    test "with an image set, serves the file", %{conn: conn, scope: scope, recipe: recipe} do
      path = temp_png!("hello")
      {:ok, recipe} = Meals.set_recipe_image(scope, recipe, path)

      conn = get(conn, ~p"/recipes/#{recipe}/image")

      assert conn.status == 200
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "image/png"

      File.rm(path)
    end

    test "with no image set, returns 404", %{conn: conn, recipe: recipe} do
      conn = get(conn, ~p"/recipes/#{recipe}/image")
      assert conn.status == 404
    end
  end

  defp temp_png!(contents) do
    path =
      Path.join(
        System.tmp_dir!(),
        "recipe-image-controller-test-#{System.unique_integer([:positive])}.png"
      )

    File.write!(path, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> contents)
    path
  end
end
