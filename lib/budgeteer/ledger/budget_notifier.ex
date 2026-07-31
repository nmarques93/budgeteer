defmodule Budgeteer.Ledger.BudgetNotifier do
  @moduledoc """
  Delivers the "you've gone over budget" email. Mirrors
  `Budgeteer.Households.UserNotifier`'s plain-text delivery pattern.
  """

  use Gettext, backend: BudgeteerWeb.Gettext

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
  `recipient_locale` is that member's own saved preference (may be `nil`,
  meaning "en") — this runs in an Oban job process, which has no locale of
  its own, so each recipient's email must explicitly request its language
  rather than relying on whatever the process happens to default to.
  """
  def deliver_budget_alert(recipient_email, recipient_locale, category, spent_cents) do
    Gettext.with_locale(BudgeteerWeb.Gettext, recipient_locale || "en", fn ->
      deliver(
        recipient_email,
        gettext("Budget alert: %{name}", name: category.name),
        """

        ==============================

        #{gettext("Hi,")}

        #{gettext("Your \"%{name}\" budget for this month is %{budget}.",
        name: category.name,
        budget: Budgeteer.Money.format(category.budget_cents))}
        #{gettext("You've spent %{amount} so far this month.", amount: Budgeteer.Money.format(spent_cents))}

        ==============================
        """
      )
    end)
  end
end
