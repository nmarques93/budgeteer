defmodule BudgeteerWeb.TransactionExportController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Ledger
  alias Budgeteer.Money
  alias BudgeteerWeb.TransactionLive.FilterForm

  @header ~w(Date Account Amount Merchant Description Category Notes)

  # A plain GET, not a LiveView — same "plain HTTP for a file operation"
  # precedent as StatementController's upload. Reuses FilterForm so the
  # same query params TransactionLive.Search/Index already put on the URL
  # (via export_query/2) filter the export identically to what's on screen.
  def download(conn, params) do
    scope = conn.assigns.current_scope
    filters = params |> FilterForm.normalize_params() |> FilterForm.to_filters()

    accounts = scope |> Ledger.list_accounts() |> Map.new(&{&1.id, &1.name})
    categories = scope |> Ledger.list_categories() |> Map.new(&{&1.id, &1.name})

    csv =
      scope
      |> Ledger.search_transactions(filters)
      |> Enum.map(&csv_row(&1, accounts, categories))
      |> then(&[@header | &1])
      |> Enum.map_join("\r\n", &encode_row/1)
      |> Kernel.<>("\r\n")

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="transactions.csv"))
    |> send_resp(200, csv)
  end

  defp csv_row(transaction, accounts, categories) do
    [
      Date.to_iso8601(transaction.date),
      Map.get(accounts, transaction.account_id, ""),
      Money.to_decimal_string(transaction.amount_cents),
      transaction.merchant,
      transaction.description,
      Map.get(categories, transaction.category_id, "Uncategorized"),
      transaction.notes
    ]
  end

  defp encode_row(fields), do: Enum.map_join(fields, ",", &encode_field/1)

  defp encode_field(nil), do: ""

  defp encode_field(value) do
    string = to_string(value)

    if String.contains?(string, [",", "\"", "\n", "\r"]) do
      ~s(") <> String.replace(string, ~s("), ~s("")) <> ~s(")
    else
      string
    end
  end
end
