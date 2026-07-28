defmodule BudgeteerWeb.MCP.Tools.ListAccounts do
  @moduledoc "List the household's accounts and their current balances."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Budgeteer.Ledger

  schema do
    %{}
  end

  @impl true
  def execute(_params, frame) do
    accounts =
      frame.assigns.scope
      |> Ledger.list_accounts()
      |> Enum.map(fn account ->
        %{
          name: account.name,
          bank_name: account.bank_name,
          currency: account.currency,
          balance: Budgeteer.Money.format(Ledger.current_balance_cents(account))
        }
      end)

    {:reply, Response.tool() |> Response.json(accounts), frame}
  end
end
