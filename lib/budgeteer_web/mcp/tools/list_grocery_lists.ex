defmodule BudgeteerWeb.MCP.Tools.ListGroceryLists do
  @moduledoc "List the household's active grocery lists and their items."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Budgeteer.Groceries

  schema do
    %{}
  end

  @impl true
  def execute(_params, frame) do
    scope = frame.assigns.scope

    lists =
      scope
      |> Groceries.list_grocery_lists()
      |> Enum.map(fn grocery_list ->
        items =
          scope
          |> Groceries.list_items(grocery_list)
          |> Enum.map(fn item ->
            %{
              name: item.name,
              quantity: item.quantity && Decimal.to_string(item.quantity),
              unit: item.unit,
              checked: item.checked
            }
          end)

        %{name: grocery_list.name, items: items}
      end)

    {:reply, Response.tool() |> Response.json(lists), frame}
  end
end
