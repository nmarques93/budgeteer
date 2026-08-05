defmodule BudgeteerWeb.MCP.Permissions do
  alias Anubis.MCP.Error

  def allow?(frame, scope) do
    access_token = frame.assigns[:access_token]
    access_token && scope in access_token.scopes
  end

  def denied(frame, scope) do
    {:error, Error.execution("This access token does not grant the #{scope} scope."), frame}
  end
end
