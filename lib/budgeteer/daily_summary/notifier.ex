defmodule Budgeteer.DailySummary.Notifier do
  @moduledoc """
  Delivers the daily morning summary by email and push. Mirrors
  `Budgeteer.Ledger.BudgetNotifier`'s plain-text delivery pattern exactly
  — the summary variant is already generated for the recipient's locale, and
  the surrounding subject/greeting is localized independently as well.
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
  Emails a household member their morning summary.
  """
  def deliver_daily_summary(recipient_email, recipient_locale, summary_text) do
    Gettext.with_locale(BudgeteerWeb.Gettext, recipient_locale || "en", fn ->
      deliver(
        recipient_email,
        gettext("Your morning summary"),
        """

        ==============================

        #{gettext("Good morning,")}

        #{summary_text}

        ==============================
        """
      )
    end)
  end

  @doc """
  Builds the `%{title:, body:}` push payload for the same summary, via
  `Budgeteer.Push` — same per-recipient locale reasoning as
  `deliver_daily_summary/3` above.
  """
  def push_payload(recipient_locale, summary_text) do
    Gettext.with_locale(BudgeteerWeb.Gettext, recipient_locale || "en", fn ->
      %{title: gettext("Your morning summary"), body: summary_text}
    end)
  end
end
