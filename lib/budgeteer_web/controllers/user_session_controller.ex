defmodule BudgeteerWeb.UserSessionController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Households
  alias Budgeteer.RateLimit
  alias BudgeteerWeb.UserAuth

  # No account lockout exists (nor should it — that's its own DoS vector),
  # so this is the only thing standing between a guessed password/token and
  # unlimited attempts. Scoped per-IP, not per-account, since the request
  # carries no reliable account identifier before it's actually checked.
  @attempt_scale :timer.minutes(5)
  @attempt_limit 10

  def create(conn, %{"_action" => "confirmed"} = params) do
    conn |> maybe_store_return_to(params) |> create(params, "User confirmed successfully.")
  end

  def create(conn, params) do
    conn |> maybe_store_return_to(params) |> create(params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    if rate_limited?(conn, "login:magic") do
      too_many_requests(conn)
    else
      case Households.login_user_by_magic_link(token) do
        {:ok, {user, tokens_to_disconnect}} ->
          UserAuth.disconnect_sessions(tokens_to_disconnect)

          conn
          |> put_flash(:info, info)
          |> UserAuth.log_in_user(user, user_params)

        _ ->
          conn
          |> put_flash(:error, "The link is invalid or it has expired.")
          |> redirect(to: ~p"/users/log-in")
      end
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if rate_limited?(conn, "login:password") do
      too_many_requests(conn)
    else
      if user = Households.get_user_by_email_and_password(email, password) do
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)
      else
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
      end
    end
  end

  defp rate_limited?(conn, bucket) do
    key = "#{bucket}:#{ip_string(conn)}"
    match?({:error, :rate_limited}, RateLimit.check(key, @attempt_scale, @attempt_limit))
  end

  defp ip_string(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp too_many_requests(conn) do
    conn
    |> put_flash(:error, "Too many attempts — please wait a few minutes and try again.")
    |> redirect(to: ~p"/users/log-in")
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Households.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Households.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  # `return_to` arrives as a plain query/form param (set as a hidden field by
  # UserLive.Login / UserLive.Confirmation from the ?return_to= they were
  # given — see UserAuth.on_mount(:require_sudo_mode, ...)). Only accept an
  # internal path to avoid an open-redirect via an attacker-supplied URL.
  defp maybe_store_return_to(conn, %{"return_to" => "/" <> _ = return_to}) do
    if String.starts_with?(return_to, "//") do
      conn
    else
      put_session(conn, :user_return_to, return_to)
    end
  end

  defp maybe_store_return_to(conn, _params), do: conn

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
