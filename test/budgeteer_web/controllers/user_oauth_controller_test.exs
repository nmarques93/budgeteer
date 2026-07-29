defmodule BudgeteerWeb.UserOAuthControllerTest do
  use BudgeteerWeb.ConnCase, async: true

  import Budgeteer.HouseholdsFixtures
  alias Budgeteer.Households
  alias BudgeteerWeb.UserOAuthController

  # The real `/auth/google` -> Google -> `/auth/google/callback` round trip
  # is Ueberauth's own already-tested behavior, not this app's. So instead
  # of dispatching through the router (where `plug Ueberauth` would try to
  # exchange a real OAuth code), we call the controller action directly and
  # manually assign what Ueberauth would have assigned on success/failure.
  defp with_test_session(conn) do
    conn
    |> Map.put(:secret_key_base, BudgeteerWeb.Endpoint.config(:secret_key_base))
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Phoenix.Controller.fetch_flash([])
  end

  defp oauth_auth(email, name \\ "Ada Lovelace") do
    %Ueberauth.Auth{
      uid: "google-#{email}",
      provider: :google,
      info: %Ueberauth.Auth.Info{email: email, name: name}
    }
  end

  describe "callback/2 — success" do
    test "logs in an existing user", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> with_test_session()
        |> assign(:ueberauth_auth, oauth_auth(user.email))
        |> UserOAuthController.callback(%{})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "creates a new household as owner for a brand-new email", %{conn: conn} do
      email = unique_user_email()

      conn =
        conn
        |> with_test_session()
        |> assign(:ueberauth_auth, oauth_auth(email))
        |> UserOAuthController.callback(%{})

      assert get_session(conn, :user_token)
      assert user = Households.get_user_by_email(email)
      assert user.role == :owner
    end

    test "redirects to the stashed return_to path (e.g. a sudo-mode reauth back to Settings)", %{
      conn: conn
    } do
      user = user_fixture()

      conn =
        conn
        |> with_test_session()
        |> put_session(:oauth_return_to, ~p"/users/settings")
        |> assign(:ueberauth_auth, oauth_auth(user.email))
        |> UserOAuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/settings"
      refute get_session(conn, :oauth_return_to)
    end

    test "joins the invite's household as a member when the stashed invite token matches", %{
      conn: conn
    } do
      inviter = user_fixture()
      invitee_email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Households.deliver_household_invite(inviter, invitee_email, url)
        end)

      conn =
        conn
        |> with_test_session()
        |> put_session(:oauth_invite_token, token)
        |> assign(:ueberauth_auth, oauth_auth(invitee_email))
        |> UserOAuthController.callback(%{})

      assert user = Households.get_user_by_email(invitee_email)
      assert user.household_id == inviter.household_id
      assert user.role == :member
      refute get_session(conn, :oauth_invite_token)
    end
  end

  describe "callback/2 — failure" do
    test "redirects to the login page with an error flash", %{conn: conn} do
      conn =
        conn
        |> with_test_session()
        |> assign(:ueberauth_failure, %Ueberauth.Failure{provider: :google, errors: []})
        |> UserOAuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not authenticate"
    end
  end
end
