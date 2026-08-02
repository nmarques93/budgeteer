defmodule Budgeteer.AI.DeepSeekClientBehaviour do
  @moduledoc """
  Behaviour for the DeepSeek client used to turn a household's spending
  data into a handful of natural-language budget insights. Lets
  `Budgeteer.Insights` depend on a configured implementation
  (`Application.get_env(:budgeteer, :insights_client, Budgeteer.AI.DeepSeekClient)`)
  so tests can swap in a Mox mock instead of hitting the real API — same
  pattern as `Budgeteer.AI.ClientBehaviour`, but named for the capability
  (`insights_client`), not the provider, so a future provider swap doesn't
  need a config-key rename.
  """

  @callback generate_insights(data :: map()) :: {:ok, [String.t()]} | {:error, term()}
end
