defmodule BudgeteerWeb.GoogleCalendarControllerTest do
  use BudgeteerWeb.ConnCase

  import Budgeteer.HouseholdsFixtures

  test "rejects a callback with an invalid OAuth state", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> get("/users/settings/google-calendar/callback?code=code&state=wrong")

    assert redirected_to(conn) == "/users/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "could not be verified"
  end
end
