defmodule Budgeteer.AI.ClientBehaviour do
  @moduledoc """
  Behaviour for the Claude API client — the vision/document AI backend,
  used only for tasks that need to actually see a file: bank statement
  parsing and (once built) photo/PDF recipe parsing. Text-only recipe
  parsing lives on `Budgeteer.AI.DeepSeekClientBehaviour` instead. Lets
  callers (`Budgeteer.Statements.ParseWorker`, and eventually a
  file-upload recipe flow) depend on a configured implementation
  (`Application.get_env(:budgeteer, :ai_client, Budgeteer.AI.Client)`) so
  tests can swap in a Mox mock instead of hitting the real API.
  """

  @callback parse_statement(
              file_bytes :: binary(),
              media_type :: String.t(),
              category_names :: [String.t()]
            ) ::
              {:ok, map()} | {:error, term()}

  @callback parse_recipe_from_file(file_bytes :: binary(), media_type :: String.t()) ::
              {:ok, map()} | {:error, term()}
end
