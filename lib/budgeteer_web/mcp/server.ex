defmodule BudgeteerWeb.MCP.Server do
  @moduledoc """
  Read-only MCP server exposing this household's budget, grocery, and meal
  data to MCP clients (Claude Desktop, etc.), authenticated by a personal
  access token — see `BudgeteerWeb.MCPAuthPlug`.

  Every tool reads `frame.assigns.scope`, set by the auth plug from the
  token's owning user. No tool accepts a household/user identifier as an
  argument, so a client can never query outside the token's own household.
  """

  use Anubis.Server,
    name: "Budgeteer",
    version: "1.0.0",
    capabilities: [:tools]

  alias BudgeteerWeb.MCP.Tools

  component Tools.ListAccounts
  component Tools.ListRecentTransactions
  component Tools.MonthlySpending
  component Tools.ListGroceryLists
  component Tools.ListRecipes

  @impl true
  def init(_client_info, frame) do
    {:ok, frame}
  end
end
