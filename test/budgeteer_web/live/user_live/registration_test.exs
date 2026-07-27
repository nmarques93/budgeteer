defmodule BudgeteerWeb.UserLive.RegistrationTest do
  use BudgeteerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Budgeteer.HouseholdsFixtures

  alias Budgeteer.{Households, Repo}
  alias Budgeteer.Households.Household

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces"})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "register via household invite" do
    setup do
      inviter = user_fixture()
      invitee_email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Households.deliver_household_invite(inviter, invitee_email, url)
        end)

      household = Repo.get!(Household, inviter.household_id)

      %{token: token, invitee_email: invitee_email, household: household}
    end

    test "shows the household name and locks the email", %{
      conn: conn,
      token: token,
      invitee_email: invitee_email,
      household: household
    } do
      {:ok, _lv, html} = live(conn, ~p"/users/register?#{[token: token]}")

      assert html =~ household.name
      assert html =~ invitee_email
      refute html =~ "Household name"
    end

    test "joins the existing household as a member", %{
      conn: conn,
      token: token,
      invitee_email: invitee_email,
      household: household
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register?#{[token: token]}")

      form = form(lv, "#registration_form")

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ ~r/An email was sent to .*, please access it to confirm your account/

      user = Households.get_user_by_email(invitee_email)
      assert user.household_id == household.id
      assert user.role == :member
      assert Repo.aggregate(Household, :count) == 1
    end

    test "falls back to normal registration with an invalid token", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register?#{[token: "garbage"]}")

      assert html =~ "This invite link is invalid or has expired."
      assert html =~ "Household name"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end
end
