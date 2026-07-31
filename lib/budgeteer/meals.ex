defmodule Budgeteer.Meals do
  @moduledoc """
  The Meals context — recipes and a household's meal plan. Recipe
  ingredients are an `embeds_many`, not a separate table: they have no
  independent lifecycle (no checked state, never queried across
  recipes, always read/written with their parent recipe).
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo

  alias Budgeteer.Meals.{Recipe, PlannedMeal}
  alias Budgeteer.Groceries
  alias Budgeteer.Groceries.GroceryList
  alias Budgeteer.Households.Scope

  ## Recipes

  @doc """
  Subscribes to scoped notifications about recipe changes.

  The broadcasted messages match the pattern:

    * {:created, %Recipe{}}
    * {:updated, %Recipe{}}
    * {:deleted, %Recipe{}}

  """
  def subscribe_recipes(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{scope.user.household_id}:recipes")
  end

  defp broadcast_recipe(household_id, message) do
    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{household_id}:recipes", message)
  end

  @doc """
  Returns the household's recipes.
  """
  def list_recipes(%Scope{} = scope) do
    Repo.all_by(Recipe, household_id: scope.user.household_id)
  end

  @doc """
  Gets a single recipe, scoped to the household.
  """
  def get_recipe!(%Scope{} = scope, id) do
    Repo.get_by!(Recipe, id: id, household_id: scope.user.household_id)
  end

  @doc """
  Creates a recipe.
  """
  def create_recipe(%Scope{} = scope, attrs) do
    with {:ok, recipe = %Recipe{}} <-
           %Recipe{}
           |> Recipe.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_recipe(recipe.household_id, {:created, recipe})
      {:ok, recipe}
    end
  end

  @doc """
  Updates a recipe.
  """
  def update_recipe(%Scope{} = scope, %Recipe{} = recipe, attrs) do
    true = recipe.household_id == scope.user.household_id

    with {:ok, recipe = %Recipe{}} <-
           recipe
           |> Recipe.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_recipe(recipe.household_id, {:updated, recipe})
      {:ok, recipe}
    end
  end

  @doc """
  Deletes a recipe.
  """
  def delete_recipe(%Scope{} = scope, %Recipe{} = recipe) do
    true = recipe.household_id == scope.user.household_id

    with {:ok, recipe = %Recipe{}} <- Repo.delete(recipe) do
      broadcast_recipe(recipe.household_id, {:deleted, recipe})
      {:ok, recipe}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking recipe changes.
  """
  def change_recipe(%Scope{} = scope, %Recipe{} = recipe, attrs \\ %{}) do
    Recipe.changeset(recipe, attrs, scope)
  end

  ## Meal plan

  @doc """
  Subscribes to scoped notifications about the meal plan.

  The broadcasted messages match the pattern:

    * {:created, %PlannedMeal{}}
    * {:deleted, %PlannedMeal{}}

  """
  def subscribe_planned_meals(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(
      Budgeteer.PubSub,
      "household:#{scope.user.household_id}:planned_meals"
    )
  end

  defp broadcast_planned_meal(household_id, message) do
    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{household_id}:planned_meals", message)
  end

  @doc """
  Returns the household's upcoming planned meals (today onward),
  soonest first, with the recipe preloaded.
  """
  def list_planned_meals(%Scope{} = scope) do
    query =
      from pm in PlannedMeal,
        where: pm.household_id == ^scope.user.household_id,
        where: pm.date >= ^Date.utc_today(),
        order_by: [asc: pm.date],
        preload: :recipe

    Repo.all(query)
  end

  @doc """
  Plans a meal: assigns a recipe to a date.
  """
  def create_planned_meal(%Scope{} = scope, attrs) do
    with {:ok, planned_meal = %PlannedMeal{}} <-
           %PlannedMeal{}
           |> PlannedMeal.changeset(attrs, scope)
           |> Repo.insert() do
      planned_meal = Repo.preload(planned_meal, :recipe)
      broadcast_planned_meal(planned_meal.household_id, {:created, planned_meal})
      {:ok, planned_meal}
    end
  end

  @doc """
  Removes a meal from the plan.
  """
  def delete_planned_meal(%Scope{} = scope, %PlannedMeal{} = planned_meal) do
    true = planned_meal.household_id == scope.user.household_id

    with {:ok, planned_meal = %PlannedMeal{}} <- Repo.delete(planned_meal) do
      broadcast_planned_meal(planned_meal.household_id, {:deleted, planned_meal})
      {:ok, planned_meal}
    end
  end

  @doc """
  Adds every ingredient from the given recipes to a grocery list, via
  `Budgeteer.Groceries.create_item/3` — no duplicate item-creation
  logic. `recipes` is a list, so this covers both "add this one
  recipe's ingredients" (a single-element list) and "add everything
  in the meal plan" (every planned meal's recipe) with the same code
  path. Repeated ingredients across recipes are not de-duplicated.

  Returns `{:ok, count}` where `count` is how many items were added.
  """
  def add_ingredients_to_grocery_list(%Scope{} = scope, recipes, %GroceryList{} = grocery_list)
      when is_list(recipes) do
    count =
      for recipe <- recipes,
          ingredient <- recipe.ingredients do
        {:ok, _item} =
          Groceries.create_item(scope, grocery_list, %{
            "name" => ingredient.name,
            "quantity" => ingredient.quantity,
            "unit" => ingredient.unit
          })

        1
      end
      |> length()

    {:ok, count}
  end
end
