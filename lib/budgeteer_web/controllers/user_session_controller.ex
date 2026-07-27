defmodule BudgeteerWeb.UserSessionController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Households
  alias BudgeteerWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    conn |> maybe_store_return_to(params) |> create(params, "User confirmed successfully.")
  end

  def create(conn, params) do
    conn |> maybe_store_return_to(params) |> create(params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
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

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

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
