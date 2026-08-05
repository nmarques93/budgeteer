defmodule Budgeteer.DailySummary.Worker do
  @moduledoc """
  Oban cron worker (see `Oban.Plugins.Cron` in `config/config.exs`) that
  generates and delivers every household's daily morning summary, once a
  day. Unlike `Budgeteer.Ledger.BudgetAlertWorker` (triggered per
  transaction, one household at a time), this is a fan-out job: it
  enumerates every household itself and handles each independently, so
  one household's AI failure can never block another's summary. Delivery is
  delegated to unique per-recipient jobs, so this parent can retry enqueue
  failures without resending a delivery that already completed.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias Budgeteer.{Households, DailySummary}
  alias Budgeteer.DailySummary.DeliveryWorker

  @impl true
  def perform(%Oban.Job{}) do
    failures =
      Households.list_household_ids()
      |> Enum.map(&run_for_household/1)
      |> Enum.filter(&match?({:error, _}, &1))

    case failures do
      [] -> :ok
      failures -> {:error, {:delivery_enqueue_failures, failures}}
    end
  end

  defp run_for_household(household_id) do
    case DailySummary.generate_summary_for_household(household_id) do
      {:ok, summary} ->
        notify_household(household_id, summary.summary)

      {:error, reason} ->
        Logger.warning(
          "Daily summary generation failed for household #{household_id}: #{inspect(reason)}"
        )

        :ok
    end
  rescue
    exception ->
      Logger.error(
        "Daily summary worker crashed for household #{household_id}: #{Exception.message(exception)}"
      )

      {:error, {:household_crash, household_id, exception}}
  end

  defp notify_household(household_id, summary_text) do
    date = Date.to_iso8601(Date.utc_today())

    deliveries =
      Enum.map(Households.list_household_emails(household_id), fn %{email: email, locale: locale} ->
        %{
          "channel" => "email",
          "recipient_email" => email,
          "recipient_locale" => locale,
          "summary" => summary_text,
          "dedupe_key" => "daily-summary:#{household_id}:#{date}:email:#{email}"
        }
      end) ++
        Enum.map(Households.list_household_device_tokens(household_id), fn %{token: token, locale: locale} ->
          %{
            "channel" => "push",
            "device_token" => token,
            "recipient_locale" => locale,
            "summary" => summary_text,
            "dedupe_key" => "daily-summary:#{household_id}:#{date}:push:#{token}"
          }
        end)

    Enum.reduce_while(deliveries, :ok, fn args, :ok ->
      job =
        DeliveryWorker.new(args,
          unique: [fields: [:args, :worker], keys: [:dedupe_key], period: :infinity]
        )

      case Oban.insert(job) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
