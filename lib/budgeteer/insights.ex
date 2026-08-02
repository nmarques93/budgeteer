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
    Repo.get_by(BudgetInsight, household_id: scope.user.household_id)
  end

  @doc """
  Generates fresh insights for the household: gathers this month's
  category spend (and the prior 3 months, as a "usual" baseline) from
  `Budgeteer.Ledger`, asks the configured insights client to pick out
  what's notable, and stores the result (one row per household — this
  replaces any previous insights, it doesn't keep history).
  """
  def generate_insights(%Scope{} = scope) do
    data = build_insight_data(scope)

    with {:ok, insights} <- insights_client().generate_insights(data) do
      upsert_insights(scope, insights)
    end
  end

  defp upsert_insights(%Scope{} = scope, insights) do
    attrs = %{
      household_id: scope.user.household_id,
      insights: insights,
      generated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    %BudgetInsight{}
    |> Ecto.Changeset.cast(attrs, [:household_id, :insights, :generated_at])
    |> Ecto.Changeset.unique_constraint(:household_id)
    |> Repo.insert(
      on_conflict: {:replace, [:insights, :generated_at, :updated_at]},
      conflict_target: :household_id,
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
  # this app (parse_statement/parse_recipe) follows the same rule: the
  # model extracts/summarizes stated facts, it never computes them.
  defp build_insight_data(%Scope{} = scope) do
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
      "balance_30_days_ago" => balance_30_days_ago(balance_history)
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

  defp insights_client,
    do: Application.get_env(:budgeteer, :insights_client, Budgeteer.AI.DeepSeekClient)
end
