defmodule Budgeteer.Insights do
  @moduledoc """
  Budget insights — a household's spending data reduced to a handful of
  natural-language observations ("you're pacing 23% over your usual
  Groceries spend this month") via `Budgeteer.AI.DeepSeekClient`. Unlike
  `Budgeteer.AI.Client` (Anthropic, used for document extraction), this
  never asks the model to do arithmetic — all the pacing/comparison math
  happens here in Elixir first, and the model only picks out which
  already-computed facts are worth mentioning and phrases them in plain
  language. Deliberately manual-refresh only for v1 (no Oban cron job) —
  see CLAUDE.md for the reasoning.
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo
  alias Budgeteer.Insights.BudgetInsight
  alias Budgeteer.Households
  alias Budgeteer.Households.Scope
  alias Budgeteer.Ledger
  alias Budgeteer.Money

  @doc """
  Subscribes to scoped notifications about a household's budget insights.

  The broadcasted messages match the pattern:

    * {:updated, %BudgetInsight{}}

  """
  def subscribe_insights(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(
      Budgeteer.PubSub,
      "household:#{scope.user.household_id}:budget_insights"
    )
  end

  defp broadcast_insights(household_id, message) do
    Phoenix.PubSub.broadcast(
      Budgeteer.PubSub,
      "household:#{household_id}:budget_insights",
      message
    )
  end

  @doc """
  Returns the household's most recently generated insights, or `nil` if
  none have been generated yet.
  """
  def get_insights(%Scope{} = scope) do
    Repo.get_by(BudgetInsight,
      household_id: scope.user.household_id,
      locale: user_locale(scope)
    )
  end

  @doc """
  Generates fresh insights for the household: gathers this month's
  category spend (and the prior 3 months, as a "usual" baseline) from
  `Budgeteer.Ledger`, asks the configured insights client to pick out
  what's notable, and stores one localized row per household locale — this
  replaces the previous insight for that locale, it doesn't keep history.
  """
  def generate_insights(%Scope{} = scope) do
    locales = Households.list_household_locales(scope.user.household_id)

    with {:ok, localized_insights} <- generate_for_locales(scope, locales),
         {:ok, stored} <- store_localized_insights(scope, localized_insights) do
      {:ok, Enum.find(stored, &(&1.locale == user_locale(scope)))}
    end
  end

  defp generate_for_locales(scope, locales) do
    Enum.reduce_while(locales, {:ok, []}, fn locale, {:ok, acc} ->
      data = build_insight_data(scope, locale)

      case deepseek_client().generate_insights(data) do
        {:ok, insights} -> {:cont, {:ok, [{locale, insights} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp store_localized_insights(%Scope{} = scope, localized_insights) do
    localized_insights
    |> Enum.map(fn {locale, insights} -> upsert_insights(scope, locale, insights) end)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, insight}, {:ok, acc} -> {:cont, {:ok, [insight | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp upsert_insights(%Scope{} = scope, locale, insights) do
    attrs = %{
      household_id: scope.user.household_id,
      insights: insights,
      locale: locale,
      generated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    %BudgetInsight{}
    |> Ecto.Changeset.cast(attrs, [:household_id, :insights, :locale, :generated_at])
    |> Repo.insert(
      on_conflict: {:replace, [:insights, :generated_at, :updated_at]},
      conflict_target: [:household_id, :locale],
      returning: true
    )
    |> case do
      {:ok, budget_insight} ->
        broadcast_insights(budget_insight.household_id, {:updated, budget_insight})
        {:ok, budget_insight}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # All the pacing/comparison arithmetic happens here, not in the prompt —
  # LLMs are unreliable at precise math, and every other AI feature in
  # this app (AI.Client's parse_statement/parse_recipe_from_file,
  # DeepSeekClient's parse_recipe) follows the same rule: the model
  # extracts/summarizes stated facts, it never computes them.
  defp build_insight_data(%Scope{} = scope, locale) do
    today = Date.utc_today()
    day_of_month = today.day
    days_in_month = Date.days_in_month(today)
    pace_factor = days_in_month / day_of_month

    current = expense_totals(scope, today)
    usual_by_name = usual_averages(scope, today)

    categories =
      Enum.map(current, fn row ->
        spent_cents = abs(row.total_cents)
        projected_cents = round(spent_cents * pace_factor)
        usual_cents = Map.get(usual_by_name, row.name)

        %{
          "name" => row.name,
          "budget" => format_or_nil(row.budget_cents),
          "month_to_date_spend" => Money.format(-spent_cents),
          "projected_month_end_spend" => Money.format(-projected_cents),
          "usual_monthly_spend" => usual_cents && Money.format(-usual_cents)
        }
      end)

    balance_history = Ledger.balance_history(scope, 30)

    %{
      "today" => Date.to_iso8601(today),
      "day_of_month" => day_of_month,
      "days_in_month" => days_in_month,
      "categories" => categories,
      "current_balance" => Money.format(Ledger.total_balance_cents(scope)),
      "balance_30_days_ago" => balance_30_days_ago(balance_history),
      "locale" => locale
    }
  end

  defp expense_totals(scope, date) do
    scope
    |> Ledger.monthly_category_totals(date)
    |> Enum.filter(&(&1.type == :expense))
    |> Enum.map(&Map.update!(&1, :total_cents, fn cents -> Decimal.to_integer(cents) end))
  end

  # Averages each category's spend across the past 3 complete months,
  # treating a month with no spend in that category as 0 (not skipping
  # it) — a category that's usually ~€0 and had one big month shouldn't
  # look like a €0 "usual" baseline just because absent months got
  # excluded from the average.
  defp usual_averages(scope, today) do
    1..3
    |> Enum.map(&expense_totals(scope, months_ago(today, &1)))
    |> List.flatten()
    |> Enum.group_by(& &1.name, & &1.total_cents)
    |> Map.new(fn {name, totals} ->
      {name, div(Enum.reduce(totals, 0, &(abs(&1) + &2)), 3)}
    end)
    |> Map.reject(fn {_name, cents} -> cents == 0 end)
  end

  defp months_ago(date, n) do
    Enum.reduce(1..n, date, fn _, acc -> Date.add(Date.beginning_of_month(acc), -1) end)
  end

  defp balance_30_days_ago([]), do: nil
  defp balance_30_days_ago([%{balance_cents: cents} | _]), do: Money.format(cents)

  defp format_or_nil(nil), do: nil
  defp format_or_nil(cents), do: Money.format(cents)

  defp user_locale(%Scope{user: %{locale: "pt_PT"}}), do: "pt_PT"
  defp user_locale(%Scope{}), do: "en"

  defp deepseek_client,
    do: Application.get_env(:budgeteer, :deepseek_client, Budgeteer.AI.DeepSeekClient)
end
