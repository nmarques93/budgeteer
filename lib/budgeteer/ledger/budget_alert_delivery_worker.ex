defmodule Budgeteer.Ledger.BudgetAlertDeliveryWorker do
  @moduledoc """
  Delivers one budget alert to one recipient and channel.

  Delivery is split from the household fan-out worker so a provider failure
  retries only the affected recipient. The dedupe key is unique forever in
  Oban, preventing a parent-job retry from sending a successful delivery twice.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Budgeteer.Ledger
  alias Budgeteer.Ledger.BudgetNotifier
  alias Budgeteer.Push

  @impl true
  def perform(%Oban.Job{args: %{"channel" => "email"} = args}) do
    category = Ledger.get_category!(args["category_id"])

    case BudgetNotifier.deliver_budget_alert(
           args["recipient_email"],
           args["recipient_locale"],
           category,
           args["spent_cents"]
         ) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"channel" => "push"} = args}) do
    category = Ledger.get_category!(args["category_id"])

    case Push.send(
           args["device_token"],
           BudgetNotifier.push_payload(
             args["recipient_locale"],
             category,
             args["spent_cents"]
           )
         ) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
