defmodule Budgeteer.DailySummary.DeliveryWorker do
  @moduledoc """
  Delivers one daily summary to one recipient and channel.

  Delivery jobs are unique by household, date, recipient, and channel, so a
  cron retry cannot resend a summary that already completed successfully.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Budgeteer.DailySummary.Notifier
  alias Budgeteer.Households
  alias Budgeteer.Push

  @impl true
  def perform(%Oban.Job{args: %{"channel" => "email"} = args}) do
    case args["recipient_user_id"] do
      user_id when is_binary(user_id) ->
        user = Households.get_user!(user_id)

        if user.daily_summary_email_enabled do
          deliver_email(args)
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  def perform(%Oban.Job{args: %{"channel" => "push"} = args}) do
    case Push.send(
           args["device_token"],
           Notifier.push_payload(args["recipient_locale"], args["summary"])
         ) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_email(args) do
    case Notifier.deliver_daily_summary(
           args["recipient_email"],
           args["recipient_locale"],
           args["summary"]
         ) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
