defmodule BudgeteerWeb.MCP.Tools.CreatePlannedMeal do
  @moduledoc """
  Plan a meal: assign an existing recipe to a date on the household's meal
  plan. Takes the recipe by name (not id) — MCP clients only ever see
  recipe names via `list_recipes`/`create_recipe`, never need to know an
  internal id.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias Budgeteer.Meals
  alias BudgeteerWeb.MCP.Tools.ChangesetError

  schema do
    %{
      recipe_name: {:required, :string},
      date: {:meta, {:required, :string}, description: "ISO-8601, e.g. \"2026-08-01\""}
    }
  end

  @impl true
  def execute(%{recipe_name: recipe_name, date: date_str}, frame) do
    scope = frame.assigns.scope

    with {:ok, date} <- parse_date(date_str),
         {:ok, recipe} <- find_recipe(scope, recipe_name),
         {:ok, planned_meal} <-
           Meals.create_planned_meal(scope, %{"recipe_id" => recipe.id, "date" => date}) do
      {:reply,
       Response.tool()
       |> Response.json(%{recipe: planned_meal.recipe.name, date: planned_meal.date}), frame}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Error.execution(ChangesetError.format(changeset)), frame}

      {:error, message} when is_binary(message) ->
        {:error, Error.execution(message), frame}
    end
  end

  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "date must be in ISO-8601 format, e.g. \"2026-08-01\""}
    end
  end

  defp find_recipe(scope, recipe_name) do
    scope
    |> Meals.list_recipes()
    |> Enum.find(&(String.downcase(&1.name) == String.downcase(recipe_name)))
    |> case do
      nil ->
        {:error, "No recipe named #{inspect(recipe_name)}. Create it first with create_recipe."}

      recipe ->
        {:ok, recipe}
    end
  end
end
