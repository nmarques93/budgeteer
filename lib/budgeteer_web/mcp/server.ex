defmodule BudgeteerWeb.MCP.Server do
  @moduledoc """
  MCP server exposing this household's budget, grocery, and meal data to
  MCP clients (Claude Desktop, etc.), authenticated by a personal access
  token — see `BudgeteerWeb.MCPAuthPlug`.

  Every tool reads `frame.assigns.scope`, set by the auth plug from the
  token's owning user. No tool accepts a household/user identifier as an
  argument, so a client can never query outside the token's own household.

  Read-only for the household's financial and grocery data (accounts,
  transactions, categories, grocery lists) — no tool can create, update, or
  delete any of that. The one exception is meal planning: `CreateRecipe`
  and `CreatePlannedMeal` are the first *write* tools, deliberately scoped
  to the lowest-stakes data in the app (recipes/ingredients/meal plan, not
  money) rather than lifting the read-only boundary everywhere at once.
  """

  use Anubis.Server,
    name: "Budgeteer",
    version: "1.0.0",
    capabilities: [:tools]

  alias BudgeteerWeb.MCP.Tools

  component(Tools.ListAccounts)
  component(Tools.ListRecentTransactions)
  component(Tools.MonthlySpending)
  component(Tools.ListGroceryLists)
  component(Tools.ListRecipes)
  component(Tools.CreateRecipe)
  component(Tools.CreatePlannedMeal)

  @impl true
  def init(_client_info, frame) do
    {:ok, frame}
  end
end
