defmodule Budgeteer.Households.UserNotifier do
  use Gettext, backend: BudgeteerWeb.Gettext

  import Swoosh.Email

  alias Budgeteer.Mailer
  alias Budgeteer.Households.User

  # Delivers the email using the application mailer.
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

  # These functions can run from any process (a request, an Oban job) with
  # whatever locale that process currently has set — which reflects the
  # *sender's* locale, not necessarily the recipient's. `Gettext.with_locale/3`
  # temporarily switches the process locale just for building this email body,
  # so the recipient reads it in their own saved preference, not the sender's.

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(%User{} = user, url) do
    with_recipient_locale(user, fn ->
      deliver(user.email, gettext("Update email instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can change your email by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't request this change, please ignore this.")}

      ==============================
      """)
    end)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(%User{} = user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    with_recipient_locale(user, fn ->
      deliver(user.email, gettext("Log in instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can log into your account by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't request this email, please ignore this.")}

      ==============================
      """)
    end)
  end

  @doc """
  Deliver instructions to join a household via an invite.
  """
  def deliver_household_invite_instructions(%User{} = inviter, invitee_email, url) do
    # No User record exists yet for the invitee, so there's no saved locale
    # to read — fall back to the inviter's, since an invite is overwhelmingly
    # likely to go to someone in the same household/country.
    Gettext.with_locale(BudgeteerWeb.Gettext, inviter.locale || "en", fn ->
      deliver(
        invitee_email,
        gettext("You've been invited to a household on Budgeteer"),
        """

        ==============================

        #{gettext("Hi,")}

        #{gettext("%{name} invited you to join their household on Budgeteer.",
        name: inviter.name || inviter.email)}

        #{gettext("You can accept the invite by visiting the URL below:")}

        #{url}

        #{gettext("If you weren't expecting this, please ignore this email.")}

        ==============================
        """
      )
    end)
  end

  defp deliver_confirmation_instructions(user, url) do
    with_recipient_locale(user, fn ->
      deliver(user.email, gettext("Confirmation instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can confirm your account by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't create an account with us, please ignore this.")}

      ==============================
      """)
    end)
  end

  defp with_recipient_locale(%User{} = user, fun) do
    Gettext.with_locale(BudgeteerWeb.Gettext, user.locale || "en", fun)
  end
end
