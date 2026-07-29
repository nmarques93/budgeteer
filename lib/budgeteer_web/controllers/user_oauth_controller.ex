defmodule BudgeteerWeb.UserOAuthController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Households
  alias BudgeteerWeb.UserAuth

  plug :stash_invite_token when action == :request
  plug :stash_return_to when action == :request
  plug Ueberauth

  # Runs before `plug Ueberauth`, since Ueberauth's own plug intercepts the
  # request and redirects to the provider before this controller's :request
  # action body would ever run — this is the only place to capture the
  # invite token before the user leaves the site. Carried through the round
  # trip via the Plug session rather than a provider `state` param.
  defp stash_invite_token(conn, _opts) do
    put_session(conn, :oauth_invite_token, conn.params["token"])
  end

  # Same reasoning as stash_invite_token — lets Google re-authentication
  # (e.g. from the sudo-mode reauth wall on /users/settings) land back
  # where the user was headed instead of always falling through to the
  # default signed-in path.
  defp stash_return_to(conn, _opts) do
    put_session(conn, :oauth_return_to, safe_return_to(conn.params["return_to"]))
  end

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Could not authenticate with Google.")
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    invite_token = get_session(conn, :oauth_invite_token)
    return_to = get_session(conn, :oauth_return_to)

    conn =
      conn
      |> delete_session(:oauth_invite_token)
      |> delete_session(:oauth_return_to)
      |> then(fn conn -> if return_to, do: put_session(conn, :user_return_to, return_to), else: conn end)

    case Households.find_or_create_oauth_user(auth, invite_token) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome!")
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not sign you in with Google.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # Mirrors UserLive.Login's safe_return_to/1 — only allow a same-site path,
  # never an absolute/protocol-relative URL (open-redirect guard).
  defp safe_return_to("/" <> _ = path) do
    if String.starts_with?(path, "//"), do: nil, else: path
  end

  defp safe_return_to(_), do: nil
end
