defmodule BudgeteerWeb.RecipeImageController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Meals

  # Same plain-multipart-POST pattern as StatementController — see
  # CLAUDE.md for why LiveView's allow_upload isn't used for uploads in
  # this codebase.
  @max_file_size 8_000_000
  @allowed_extensions ~w(.jpg .jpeg .png)

  @magic_bytes %{
    ".jpg" => <<0xFF, 0xD8, 0xFF>>,
    ".jpeg" => <<0xFF, 0xD8, 0xFF>>,
    ".png" => <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>
  }

  def create(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    recipe = Meals.get_recipe!(scope, id)

    case params["image"] do
      %Plug.Upload{} = upload ->
        handle_upload(conn, scope, recipe, upload)

      _ ->
        conn
        |> put_flash(:error, gettext("Please select an image to upload"))
        |> redirect(to: ~p"/recipes/#{recipe}")
    end
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    recipe = Meals.get_recipe!(scope, id)

    if recipe.image_path && File.exists?(recipe.image_path) do
      conn
      |> put_resp_content_type(content_type(recipe.image_path))
      |> send_file(200, recipe.image_path)
    else
      send_resp(conn, 404, "")
    end
  end

  defp handle_upload(conn, scope, recipe, %Plug.Upload{} = upload) do
    ext = upload.filename |> Path.extname() |> String.downcase()

    cond do
      ext not in @allowed_extensions ->
        conn
        |> put_flash(:error, gettext("Unsupported file type — use JPG or PNG"))
        |> redirect(to: ~p"/recipes/#{recipe}")

      File.stat!(upload.path).size > @max_file_size ->
        conn
        |> put_flash(:error, gettext("Image is too large (max 8 MB)"))
        |> redirect(to: ~p"/recipes/#{recipe}")

      not matches_magic_bytes?(ext, upload.path) ->
        conn
        |> put_flash(
          :error,
          gettext("File content doesn't match its extension — use a real JPG or PNG")
        )
        |> redirect(to: ~p"/recipes/#{recipe}")

      true ->
        save_image(conn, scope, recipe, upload, ext)
    end
  end

  defp matches_magic_bytes?(ext, path) do
    signature = Map.fetch!(@magic_bytes, ext)
    header = File.open!(path, [:read, :binary], &IO.binread(&1, byte_size(signature)))
    header == signature
  end

  defp save_image(conn, scope, recipe, upload, ext) do
    storage_dir = Application.fetch_env!(:budgeteer, :recipe_image_storage_path)
    File.mkdir_p!(storage_dir)
    image_path = Path.join(storage_dir, recipe.id <> ext)
    File.cp!(upload.path, image_path)

    case Meals.set_recipe_image(scope, recipe, image_path) do
      {:ok, _recipe} ->
        conn
        |> put_flash(:info, gettext("Image uploaded"))
        |> redirect(to: ~p"/recipes/#{recipe}")

      {:error, %Ecto.Changeset{}} ->
        File.rm(image_path)

        conn
        |> put_flash(:error, gettext("Could not save image"))
        |> redirect(to: ~p"/recipes/#{recipe}")
    end
  end

  defp content_type(path) do
    case path |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      _ -> "image/jpeg"
    end
  end
end
