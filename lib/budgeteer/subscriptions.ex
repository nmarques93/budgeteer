defmodule Budgeteer.Subscriptions do
  @moduledoc """
  Recurring-charge ("subscription") detection — the Rocket Money-style
  "here's what you're being charged for that you forgot about" hook,
  built entirely on data the ledger already has.

  Detected subscriptions are never stored. Like `Ledger.current_balance_cents/1`,
  they're computed fresh from `transactions` on every call, so there's
  nothing to keep in sync, no periodic Oban job, and no staleness to worry
  about. The only persisted state is `dismissed_subscriptions` — which
  `{merchant, amount}` patterns a household has said aren't actually a
  subscription — since that feedback can't be derived from anything else.

  Detection is deliberately narrow, since a wrong "detected subscription"
  is worse than a missed one: a `{merchant, amount}` pair (exact,
  case-insensitive match — no fuzzy merchant grouping yet, a real gap for
  banks that vary their merchant string slightly between charges, e.g.
  "NETFLIX.COM" vs "NETFLIX INTERNATIONAL B" — deliberately deferred
  rather than risking false positives from imprecise matching) needs at
  least three occurrences whose gaps all fall within a fixed tolerance of
  one recognized cadence (weekly/biweekly/monthly/quarterly/yearly) before
  it's surfaced at all.
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo
  alias Budgeteer.Ledger.Transaction
  alias Budgeteer.Subscriptions.DismissedSubscription
  alias Budgeteer.Households.Scope

  @min_occurrences 3

  # {cadence, typical gap in days, tolerance in days} — ranges deliberately
  # don't overlap, so a group of gaps matches at most one cadence.
  @cadences [
    {:weekly, 7, 2},
    {:biweekly, 14, 3},
    {:monthly, 30, 5},
    {:quarterly, 91, 10},
    {:yearly, 365, 15}
  ]

  @doc """
  Subscribes to scoped notifications about dismissed-subscription changes.

  The broadcasted messages match the pattern:

    * {:dismissed, %DismissedSubscription{}}
    * {:undismissed, %DismissedSubscription{}}

  """
  def subscribe_subscriptions(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(
      Budgeteer.PubSub,
      "household:#{scope.user.household_id}:subscriptions"
    )
  end

  defp broadcast(household_id, message) do
    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{household_id}:subscriptions", message)
  end

  @doc """
  Returns the household's detected recurring charges, excluding anything
  dismissed, sorted by amount (largest charge first). Each result is a
  plain map:

      %{merchant_key, merchant, amount_cents, cadence, occurrences,
        last_date, next_expected_date, category_id}

  `cadence` is one of `:weekly`, `:biweekly`, `:monthly`, `:quarterly`,
  `:yearly`.
  """
  def list_subscriptions(%Scope{} = scope) do
    dismissed = dismissed_keys(scope)

    scope
    |> candidate_groups()
    |> Enum.map(&build_subscription/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&MapSet.member?(dismissed, {&1.merchant_key, &1.amount_cents}))
    |> Enum.sort_by(& &1.amount_cents)
  end

  @doc """
  Converts a subscription's charge into a monthly-equivalent cost (e.g. a
  yearly €120 charge is ~€10/mo) — for the dashboard's total-cost summary
  and each row's "≈ monthly" column. Plain integer-cents rational math,
  not `Decimal` — this is a rough at-a-glance estimate, never stored or
  compared for equality, so a few cents of rounding doesn't matter.
  """
  def monthly_equivalent_cents(%{amount_cents: cents, cadence: cadence}) do
    {numerator, denominator} = monthly_multiplier(cadence)
    -((abs(cents) * numerator) |> div(denominator))
  end

  defp monthly_multiplier(:weekly), do: {52, 12}
  defp monthly_multiplier(:biweekly), do: {26, 12}
  defp monthly_multiplier(:monthly), do: {1, 1}
  defp monthly_multiplier(:quarterly), do: {1, 3}
  defp monthly_multiplier(:yearly), do: {1, 12}

  @doc """
  Marks a `{merchant_key, amount_cents}` pattern as not a subscription, so
  `list_subscriptions/1` stops surfacing it. Idempotent — dismissing an
  already-dismissed pattern is a no-op, not an error.
  """
  def dismiss(%Scope{} = scope, merchant_key, amount_cents) do
    with {:ok, dismissed} <-
           %DismissedSubscription{}
           |> DismissedSubscription.changeset(
             %{merchant_key: merchant_key, amount_cents: amount_cents},
             scope
           )
           |> Repo.insert(
             on_conflict: :nothing,
             conflict_target: [:household_id, :merchant_key, :amount_cents]
           ) do
      broadcast(scope.user.household_id, {:dismissed, dismissed})
      {:ok, dismissed}
    end
  end

  @doc "Returns the household's dismissed patterns, most recently dismissed first."
  def list_dismissed(%Scope{} = scope) do
    Repo.all(
      from d in DismissedSubscription,
        where: d.household_id == ^scope.user.household_id,
        order_by: [desc: d.inserted_at]
    )
  end

  @doc "Undoes a dismissal, so the pattern can be detected as a subscription again."
  def undismiss(%Scope{} = scope, %DismissedSubscription{} = dismissed_subscription) do
    true = dismissed_subscription.household_id == scope.user.household_id

    with {:ok, dismissed_subscription} <- Repo.delete(dismissed_subscription) do
      broadcast(scope.user.household_id, {:undismissed, dismissed_subscription})
      {:ok, dismissed_subscription}
    end
  end

  defp dismissed_keys(scope) do
    scope
    |> list_dismissed()
    |> MapSet.new(&{&1.merchant_key, &1.amount_cents})
  end

  defp candidate_groups(%Scope{} = scope) do
    Repo.all(
      from t in Transaction,
        where:
          t.household_id == ^scope.user.household_id and t.amount_cents < 0 and
            not is_nil(t.merchant) and
            t.merchant != "",
        order_by: [asc: t.date],
        select: %{
          merchant: t.merchant,
          amount_cents: t.amount_cents,
          date: t.date,
          category_id: t.category_id
        }
    )
    |> Enum.group_by(&{merchant_key(&1.merchant), &1.amount_cents})
  end

  defp merchant_key(merchant), do: merchant |> String.trim() |> String.downcase()

  defp build_subscription({{merchant_key, amount_cents}, transactions})
       when length(transactions) >= @min_occurrences do
    dates = Enum.map(transactions, & &1.date)
    gaps = gaps_in_days(dates)

    case detect_cadence(gaps) do
      nil ->
        nil

      cadence ->
        last = List.last(transactions)

        %{
          merchant_key: merchant_key,
          merchant: last.merchant,
          amount_cents: amount_cents,
          cadence: cadence,
          occurrences: length(transactions),
          last_date: last.date,
          next_expected_date: Date.add(last.date, cadence_days(cadence)),
          category_id: last.category_id
        }
    end
  end

  defp build_subscription(_group), do: nil

  defp gaps_in_days(dates) do
    dates
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> Date.diff(b, a) end)
  end

  defp detect_cadence(gaps) do
    Enum.find_value(@cadences, fn {name, center, tolerance} ->
      if Enum.all?(gaps, &(abs(&1 - center) <= tolerance)), do: name
    end)
  end

  defp cadence_days(:weekly), do: 7
  defp cadence_days(:biweekly), do: 14
  defp cadence_days(:monthly), do: 30
  defp cadence_days(:quarterly), do: 91
  defp cadence_days(:yearly), do: 365
end
