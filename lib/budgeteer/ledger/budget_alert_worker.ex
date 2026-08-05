defmodule Budgeteer.Ledger.BudgetAlertWorker do
  @moduledoc """
  Oban worker that emails every household member once a category has gone
  over its monthly budget. Sending happens here, off the request path, so a
  slow or failing mail provider can't hold up saving a transaction (the same
  reasoning as `Budgeteer.Statements.ParseWorker` keeping the AI call off
  the upload request). The "only once per month" guard already happened
  synchronously in `Budgeteer.Ledger` before this job was enqueued.

  Fans the alert out to unique per-recipient email and push delivery jobs.
  Each delivery retries independently, so one provider or recipient cannot
  prevent the rest of the household from being notified.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Budgeteer.Households
  alias Budgeteer.Ledger
  alias Budgeteer.Ledger.BudgetAlertDeliveryWorker

  @impl true
  def perform(%Oban.Job{args: %{"category_id" => category_id, "spent_cents" => spent_cents} = args}) do
    category = Ledger.get_category!(category_id)
    month = Map.get(args, "month", Date.to_iso8601(Date.utc_today()))

    deliveries =
      Enum.map(Households.list_household_emails(category.household_id), fn %{email: email, locale: locale} ->
        %{
          "channel" => "email",
          "category_id" => category.id,
          "spent_cents" => spent_cents,
          "recipient_email" => email,
          "recipient_locale" => locale,
          "dedupe_key" => "budget-alert:#{category.id}:#{month}:email:#{email}"
        }
      end) ++
        Enum.map(Households.list_household_device_tokens(category.household_id), fn %{token: token, locale: locale} ->
          %{
            "channel" => "push",
            "category_id" => category.id,
            "spent_cents" => spent_cents,
            "device_token" => token,
            "recipient_locale" => locale,
            "dedupe_key" => "budget-alert:#{category.id}:#{month}:push:#{token}"
          }
        end)

    enqueue_deliveries(deliveries)
  end

  defp enqueue_deliveries(deliveries) do
    Enum.reduce_while(deliveries, :ok, fn args, :ok ->
      job =
        BudgetAlertDeliveryWorker.new(args,
          unique: [fields: [:args, :worker], keys: [:dedupe_key], period: :infinity]
        )

      case Oban.insert(job) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
