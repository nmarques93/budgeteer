defmodule Budgeteer.Money do
  @moduledoc """
  Converts between user-facing decimal currency strings ("1500.00") and
  integer cents, for storage. Money is always stored as integer cents (see
  CLAUDE.md) — this module is the only place that boundary should be crossed.
  """

  def to_cents(nil), do: nil
  def to_cents(""), do: nil

  def to_cents(str) when is_binary(str) do
    case Decimal.parse(str) do
      {decimal, ""} -> decimal |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
      _ -> :error
    end
  end

  def to_decimal_string(nil), do: nil

  def to_decimal_string(cents) when is_integer(cents) do
    cents |> Decimal.new() |> Decimal.div(100) |> Decimal.round(2) |> Decimal.to_string(:normal)
  end

  @doc "Formats cents as a signed euro string, e.g. `-€42.50` or `€1957.50`."
  def format(nil), do: "—"
  def format(cents) when cents < 0, do: "-€" <> to_decimal_string(-cents)
  def format(cents) when is_integer(cents), do: "€" <> to_decimal_string(cents)
end
