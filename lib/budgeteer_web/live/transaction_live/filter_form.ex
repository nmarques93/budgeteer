defmodule BudgeteerWeb.TransactionLive.FilterForm do
  @moduledoc """
  Shared transaction search/filter form, used by both the per-account
  transaction list (`TransactionLive.Index`) and the cross-account search
  page (`TransactionLive.Search`). Deliberately a plain params-in/params-out
  form (not changeset-backed) since these fields filter a query, they don't
  validate or persist anything.
  """
  use Phoenix.Component
  import BudgeteerWeb.CoreComponents

  @default_params %{
    "date_from" => "",
    "date_to" => "",
    "category_id" => "",
    "query" => "",
    "amount_min" => "",
    "amount_max" => "",
    "account_id" => ""
  }

  @doc "Fills in any missing keys so every field always has a bound value."
  def normalize_params(params) do
    Map.merge(@default_params, params)
  end

  @doc """
  Converts the form's raw string params into the typed filter map expected
  by `Budgeteer.Ledger.search_transactions/2`. Unparseable dates/amounts are
  silently dropped rather than erroring — the user is still mid-typing.
  """
  def to_filters(params) do
    %{
      account_id: blank_to_nil(params["account_id"]),
      category_id: blank_to_nil(params["category_id"]),
      query: blank_to_nil(params["query"]),
      date_from: parse_date(params["date_from"]),
      date_to: parse_date(params["date_to"]),
      amount_min: parse_amount(params["amount_min"]),
      amount_max: parse_amount(params["amount_max"])
    }
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_amount(nil), do: nil
  defp parse_amount(""), do: nil

  defp parse_amount(str) do
    case Budgeteer.Money.to_cents(str) do
      cents when is_integer(cents) -> cents
      _ -> nil
    end
  end

  @doc """
  Strips blank values from the raw form params so a CSV-export link's query
  string doesn't carry empty `date_from=&date_to=&...` around. `extra` lets
  a caller inject a filter the form itself doesn't render as a field (e.g.
  `TransactionLive.Index` fixing `account_id` server-side, since its filter
  form has no account select).
  """
  def export_query(params, extra \\ %{}) do
    params
    |> Map.merge(extra)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  attr :filters, :map, required: true
  attr :categories, :list, required: true

  attr :accounts, :list,
    default: nil,
    doc: "when given, renders an account select (for cross-account search)"

  attr :event, :string, default: "filter"

  def filter_form(assigns) do
    ~H"""
    <form
      id="transaction-filters"
      phx-change={@event}
      phx-submit={@event}
      class="mb-4 grid grid-cols-2 gap-x-4 gap-y-1 sm:grid-cols-3 lg:grid-cols-4"
    >
      <.input
        :if={@accounts}
        type="select"
        name="account_id"
        label="Account"
        prompt="All accounts"
        value={@filters["account_id"]}
        options={Enum.map(@accounts, &{&1.name, &1.id})}
      />
      <.input
        type="select"
        name="category_id"
        label="Category"
        prompt="All categories"
        value={@filters["category_id"]}
        options={[{"Uncategorized", "uncategorized"} | Enum.map(@categories, &{&1.name, &1.id})]}
      />
      <.input type="date" name="date_from" label="From" value={@filters["date_from"]} />
      <.input type="date" name="date_to" label="To" value={@filters["date_to"]} />
      <.input
        type="text"
        name="query"
        label="Merchant / description"
        value={@filters["query"]}
        placeholder="e.g. Amazon"
      />
      <.input
        type="text"
        name="amount_min"
        label="Min amount"
        value={@filters["amount_min"]}
        placeholder="0.00"
      />
      <.input
        type="text"
        name="amount_max"
        label="Max amount"
        value={@filters["amount_max"]}
        placeholder="0.00"
      />
    </form>
    """
  end
end
