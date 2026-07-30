defmodule BudgeteerWeb.MCP.Tools.ChangesetError do
  @moduledoc false

  alias BudgeteerWeb.CoreComponents

  @doc """
  Formats an `%Ecto.Changeset{}`'s errors into a single human-readable
  string, for MCP tool execution-error responses (`Anubis.MCP.Error.execution/2`).
  """
  def format(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&CoreComponents.translate_error/1)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field}: #{inspect(messages)}" end)
  end
end
