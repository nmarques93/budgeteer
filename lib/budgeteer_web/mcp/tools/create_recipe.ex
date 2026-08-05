defmodule BudgeteerWeb.MCP.Tools.CreateRecipe do
  @moduledoc """
  Create a new recipe with its ingredients. The first write tool this
  server exposes — scoped deliberately narrow (recipes/ingredients/meal
  plan only, never the household's financial or grocery data, which stay
  read-only).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias Budgeteer.Meals
  alias BudgeteerWeb.MCP.Permissions
  alias BudgeteerWeb.MCP.Tools.ChangesetError

  schema do
    %{
      name: {:required, :string},
      notes: :string,
      ingredients:
        {:required,
         {:list,
          %{
            name: {:required, :string},
            quantity: {:meta, :any, description: "e.g. \"2\", \"1/2\", \"a pinch\""},
            unit: :string
          }}}
    }
  end

  @impl true
  def execute(params, frame) do
    if not Permissions.allow?(frame, "meal_write") do
      Permissions.denied(frame, "meal_write")
    else
      execute_create(params, frame)
    end
  end

  defp execute_create(params, frame) do
    attrs = %{
      "name" => params.name,
      "notes" => Map.get(params, :notes),
      "ingredients" => Enum.map(params.ingredients, &ingredient_attrs/1)
    }

    case Meals.create_recipe(frame.assigns.scope, attrs) do
      {:ok, recipe} ->
        {:reply, Response.tool() |> Response.json(%{id: recipe.id, name: recipe.name}), frame}

      {:error, changeset} ->
        {:error, Error.execution(ChangesetError.format(changeset)), frame}
    end
  end

  defp ingredient_attrs(ingredient) do
    %{
      "name" => ingredient.name,
      "quantity" => ingredient |> Map.get(:quantity) |> stringify(),
      "unit" => Map.get(ingredient, :unit)
    }
  end

  defp stringify(nil), do: nil
  defp stringify(value), do: to_string(value)
end
