defmodule Budgeteer.Ledger.BudgetAlertWorker do
  @moduledoc """
  Oban worker that emails every household member once a category has gone
  over its monthly budget. Sending happens here, off the request path, so a
  slow or failing mail provider can't hold up saving a transaction (the same
  reasoning as `Budgeteer.Statements.ParseWorker` keeping the AI call off
  the upload request). The "only once per month" guard already happened
  synchronously in `Budgeteer.Ledger` before this job was enqueued.

  Also fans the same alert out as a push notification to every registered
  device (see `Households.DeviceToken`/`Budgeteer.Push`) — additive to the
  email, never a replacement for it: `Push.send/2` no-ops silently when
  APNs isn't configured (the expected state until real Apple credentials
  are set up — see CLAUDE.md), so this worker's actual, proven delivery
  path is still email.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Budgeteer.Households
  alias Budgeteer.Ledger
  alias Budgeteer.Push

  @impl true
  def perform(%Oban.Job{args: %{"category_id" => category_id, "spent_cents" => spent_cents}}) do
    category = Ledger.get_category!(category_id)

    category.household_id
    |> Households.list_household_emails()
    |> Enum.each(fn %{email: email, locale: locale} ->
      Ledger.BudgetNotifier.deliver_budget_alert(email, locale, category, spent_cents)
    end)

    category.household_id
    |> Households.list_household_device_tokens()
    |> Enum.each(fn %{token: token, locale: locale} ->
      Push.send(token, Ledger.BudgetNotifier.push_payload(locale, category, spent_cents))
    end)

    :ok
  end
end
