defmodule Budgeteer.AI.ClientBehaviour do
  @moduledoc """
  Behaviour for the Claude API client used to parse bank statements and
  recipes. Lets callers (`Budgeteer.Statements.ParseWorker`,
  `BudgeteerWeb.RecipeLive.Extract`) depend on a configured implementation
  (`Application.get_env(:budgeteer, :ai_client, Budgeteer.AI.Client)`) so
  tests can swap in a Mox mock instead of hitting the real API.
  """

  @callback parse_statement(
              file_bytes :: binary(),
              media_type :: String.t(),
              category_names :: [String.t()]
            ) ::
              {:ok, map()} | {:error, term()}

  @callback parse_recipe(content :: {:text, String.t()} | {:file, binary(), String.t()}) ::
              {:ok, map()} | {:error, term()}
end
