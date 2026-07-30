defmodule Budgeteer.Ledger.BudgetNotifier do
  @moduledoc """
  Delivers the "you've gone over budget" email. Mirrors
  `Budgeteer.Households.UserNotifier`'s plain-text delivery pattern.
  """

  import Swoosh.Email

  alias Budgeteer.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:budgeteer, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Notifies a household member that a category has gone over its monthly
  budget. `spent_cents` is the absolute amount spent so far this month.
  """
  def deliver_budget_alert(recipient_email, category, spent_cents) do
    deliver(recipient_email, "Budget alert: #{category.name}", """

    ==============================

    Hi,

    Your "#{category.name}" budget for this month is #{Budgeteer.Money.format(category.budget_cents)}.
    You've spent #{Budgeteer.Money.format(spent_cents)} so far this month.

    ==============================
    """)
  end
end
