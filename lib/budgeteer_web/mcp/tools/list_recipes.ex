defmodule BudgeteerWeb.MCP.Tools.ListRecipes do
  @moduledoc "List the household's saved recipes and their ingredients."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Budgeteer.Meals

  schema do
    %{}
  end

  @impl true
  def execute(_params, frame) do
    recipes =
      frame.assigns.scope
      |> Meals.list_recipes()
      |> Enum.map(fn recipe ->
        %{
          name: recipe.name,
          notes: recipe.notes,
          ingredients:
            Enum.map(recipe.ingredients, fn ingredient ->
              %{
                name: ingredient.name,
                quantity: ingredient.quantity && Decimal.to_string(ingredient.quantity),
                unit: ingredient.unit
              }
            end)
        }
      end)

    {:reply, Response.tool() |> Response.json(recipes), frame}
  end
end
