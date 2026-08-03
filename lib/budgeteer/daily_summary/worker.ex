defmodule Budgeteer.DailySummary.Worker do
  @moduledoc """
  Oban cron worker (see `Oban.Plugins.Cron` in `config/config.exs`) that
  generates and delivers every household's daily morning summary, once a
  day. Unlike `Budgeteer.Ledger.BudgetAlertWorker` (triggered per
  transaction, one household at a time), this is a fan-out job: it
  enumerates every household itself and handles each independently, so
  one household's AI failure can never block or retry another's already-
  delivered summary. `max_attempts: 1` for the same reason — a retry of
  the whole job would risk re-emailing households that already succeeded
  before a later one failed; if this run genuinely fails, tomorrow's cron
  fire is the retry.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 1

  require Logger

  alias Budgeteer.{Households, DailySummary, Push}
  alias Budgeteer.DailySummary.Notifier

  @impl true
  def perform(%Oban.Job{}) do
    Households.list_household_ids()
    |> Enum.each(&run_for_household/1)

    :ok
  end

  defp run_for_household(household_id) do
    case DailySummary.generate_summary_for_household(household_id) do
      {:ok, summary} ->
        notify_household(household_id, summary.summary)

      {:error, reason} ->
        Logger.warning(
          "Daily summary generation failed for household #{household_id}: #{inspect(reason)}"
        )
    end
  rescue
    exception ->
      Logger.error(
        "Daily summary worker crashed for household #{household_id}: #{Exception.message(exception)}"
      )
  end

  defp notify_household(household_id, summary_text) do
    household_id
    |> Households.list_household_emails()
    |> Enum.each(fn %{email: email, locale: locale} ->
      Notifier.deliver_daily_summary(email, locale, summary_text)
    end)

    household_id
    |> Households.list_household_device_tokens()
    |> Enum.each(fn %{token: token, locale: locale} ->
      Push.send(token, Notifier.push_payload(locale, summary_text))
    end)
  end
end
