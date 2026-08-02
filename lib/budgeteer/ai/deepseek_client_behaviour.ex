defmodule Budgeteer.AI.DeepSeekClientBehaviour do
  @moduledoc """
  Behaviour for the DeepSeek client — the text-only AI backend, used for
  every task in this app that doesn't need to see a document/image:
  budget insights and recipe parsing from plain text (pasted, or fetched
  from a URL). Lets callers depend on a configured implementation
  (`Application.get_env(:budgeteer, :deepseek_client, Budgeteer.AI.DeepSeekClient)`)
  so tests can swap in a Mox mock instead of hitting the real API — same
  pattern as `Budgeteer.AI.ClientBehaviour`/`:ai_client`, one config key
  per backend (not per capability), since a backend commonly covers more
  than one task.
  """

  @callback generate_insights(data :: map()) :: {:ok, [String.t()]} | {:error, term()}
  @callback parse_recipe(text :: String.t()) :: {:ok, map()} | {:error, term()}
end
