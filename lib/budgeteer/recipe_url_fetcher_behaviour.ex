defmodule Budgeteer.RecipeUrlFetcherBehaviour do
  @moduledoc """
  Behaviour for fetching a recipe web page and reducing it to plain text.
  Lets `BudgeteerWeb.RecipeLive.Extract` depend on a configured
  implementation (`Application.get_env(:budgeteer, :recipe_url_fetcher,
  Budgeteer.RecipeUrlFetcher)`) so tests can swap in a Mox mock instead of
  making a real HTTP request — same pattern as `Budgeteer.AI.ClientBehaviour`.
  """

  @callback fetch(url :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
