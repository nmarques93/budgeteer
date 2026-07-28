defmodule BudgeteerWeb.UserOAuthController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Households
  alias BudgeteerWeb.UserAuth

  plug :stash_invite_token when action == :request
  plug Ueberauth

  # Runs before `plug Ueberauth`, since Ueberauth's own plug intercepts the
  # request and redirects to the provider before this controller's :request
  # action body would ever run — this is the only place to capture the
  # invite token before the user leaves the site. Carried through the round
  # trip via the Plug session rather than a provider `state` param.
  defp stash_invite_token(conn, _opts) do
    put_session(conn, :oauth_invite_token, conn.params["token"])
  end

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Could not authenticate with Google.")
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    invite_token = get_session(conn, :oauth_invite_token)
    conn = delete_session(conn, :oauth_invite_token)

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
end
