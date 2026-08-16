defmodule Budgeteer.Ledger.TransactionFingerprint do
  @doc "Builds a stable fingerprint for duplicate transaction detection."
  def build(date, amount_cents, merchant, description) do
    with date when not is_nil(date) <- normalize_date(date),
         amount when is_integer(amount) <- amount_cents do
      [date, amount, normalize_text(merchant), normalize_text(description)]
      |> Enum.join("|")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
    end
  end

  defp normalize_date(%Date{} = date), do: Date.to_iso8601(date)
  defp normalize_date(date) when is_binary(date) and date != "", do: date
  defp normalize_date(_date), do: nil

  defp normalize_text(nil), do: ""
  defp normalize_text(text), do: text |> to_string() |> String.trim() |> String.downcase()
end
