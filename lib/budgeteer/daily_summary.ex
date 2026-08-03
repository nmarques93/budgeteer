defmodule Budgeteer.DailySummary do
  @moduledoc """
  The daily morning summary — a household's plans for today (meal,
  budget, groceries, calendar) reduced to a short natural-language digest
  via `Budgeteer.AI.DeepSeekClient`, same "compute everything in Elixir,
  the model only phrases it" rule as `Budgeteer.Insights`. Generated once
  per household per day by `Budgeteer.DailySummary.Worker` (an
  `Oban.Plugins.Cron` job, not on-demand) — this context has no manual
  "generate" entry point exposed to a LiveView, only `get_summary/1` to
  read the latest one and `generate_summary_for_household/1` for the
  worker itself.
  """

  alias Budgeteer.Repo
  alias Budgeteer.DailySummary.Summary
  alias Budgeteer.Households.Scope
  alias Budgeteer.{Meals, Events, Groceries, Ledger}

  @doc """
  Subscribes to scoped notifications about a household's daily summary.

  The broadcasted messages match the pattern:

    * {:updated, %Summary{}}

  """
  def subscribe_summary(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(
      Budgeteer.PubSub,
      "household:#{scope.user.household_id}:daily_summary"
    )
  end

  defp broadcast_summary(household_id, message) do
    Phoenix.PubSub.broadcast(
      Budgeteer.PubSub,
      "household:#{household_id}:daily_summary",
      message
    )
  end

  @doc """
  Returns the household's most recently generated daily summary, or `nil`
  if none has been generated yet.
  """
  def get_summary(%Scope{} = scope) do
    Repo.get_by(Summary, household_id: scope.user.household_id)
  end

  @doc """
  Generates and stores today's summary for one household, by id (no
  scope) — this is what `Budgeteer.DailySummary.Worker` calls once per
  household, per day. Gathers today's plans from `Meals`/`Ledger`/
  `Groceries`/`Events` (each via their own unscoped, household-id-based
  helper — see each context for the "background job, no user context"
  precedent), asks the configured DeepSeek client to phrase them, and
  upserts the result (one row per household — this replaces yesterday's
  summary, it doesn't keep history).
  """
  def generate_summary_for_household(household_id) when is_binary(household_id) do
    data = build_summary_data(household_id)

    with {:ok, summary} <- deepseek_client().generate_daily_summary(data) do
      upsert_summary(household_id, summary)
    end
  end

  defp upsert_summary(household_id, summary) do
    attrs = %{
      household_id: household_id,
      summary: summary,
      generated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    %Summary{}
    |> Ecto.Changeset.cast(attrs, [:household_id, :summary, :generated_at])
    |> Ecto.Changeset.unique_constraint(:household_id)
    |> Repo.insert(
      on_conflict: {:replace, [:summary, :generated_at, :updated_at]},
      conflict_target: :household_id,
      returning: true
    )
    |> case do
      {:ok, daily_summary} ->
        broadcast_summary(daily_summary.household_id, {:updated, daily_summary})
        {:ok, daily_summary}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp build_summary_data(household_id) do
    today = Date.utc_today()

    %{
      "date" => Date.to_iso8601(today),
      "planned_meal" => planned_meal_data(household_id, today),
      "budget_categories" => budget_categories_data(household_id, today),
      "grocery_items" => grocery_items_data(household_id),
      "events" => events_data(household_id, today)
    }
  end

  defp planned_meal_data(household_id, today) do
    case Meals.get_planned_meal_for_household(household_id, today) do
      nil -> nil
      planned_meal -> planned_meal.recipe.name
    end
  end

  # Only categories that have actually reached their budget — same
  # threshold Ledger.BudgetAlertWorker itself alerts on — not every
  # category's spend, to keep the prompt (and the summary) focused on
  # what's actually worth a household member's attention this morning.
  defp budget_categories_data(household_id, today) do
    household_id
    |> Ledger.monthly_category_totals_for_household(today)
    |> Enum.filter(fn row ->
      row.type == :expense and is_integer(row.budget_cents) and
        abs(Decimal.to_integer(row.total_cents)) >= row.budget_cents
    end)
    |> Enum.map(fn row ->
      %{
        "name" => row.name,
        "spent" => Budgeteer.Money.format(-abs(Decimal.to_integer(row.total_cents))),
        "budget" => Budgeteer.Money.format(row.budget_cents)
      }
    end)
  end

  defp grocery_items_data(household_id) do
    household_id
    |> Groceries.list_unchecked_items_for_household()
    |> Enum.map(& &1.name)
  end

  defp events_data(household_id, today) do
    household_id
    |> Events.list_events_for_household(today)
    |> Enum.map(& &1.title)
  end

  defp deepseek_client,
    do: Application.get_env(:budgeteer, :deepseek_client, Budgeteer.AI.DeepSeekClient)
end
