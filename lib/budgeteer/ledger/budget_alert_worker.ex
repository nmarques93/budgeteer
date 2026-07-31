defmodule Budgeteer.Ledger.BudgetAlertWorker do
  @moduledoc """
  Oban worker that emails every household member once a category has gone
  over its monthly budget. Sending happens here, off the request path, so a
  slow or failing mail provider can't hold up saving a transaction (the same
  reasoning as `Budgeteer.Statements.ParseWorker` keeping the AI call off
  the upload request). The "only once per month" guard already happened
  synchronously in `Budgeteer.Ledger` before this job was enqueued.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Budgeteer.Households
  alias Budgeteer.Ledger

  @impl true
  def perform(%Oban.Job{args: %{"category_id" => category_id, "spent_cents" => spent_cents}}) do
    category = Ledger.get_category!(category_id)

    category.household_id
    |> Households.list_household_emails()
    |> Enum.each(fn %{email: email, locale: locale} ->
      Ledger.BudgetNotifier.deliver_budget_alert(email, locale, category, spent_cents)
    end)

    :ok
  end
end
