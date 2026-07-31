defmodule BudgeteerWeb.PageControllerTest do
  use BudgeteerWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Your bank statement, turned into a ledger you can trust."
    assert html =~ ~p"/users/register"
  end

  test "the iOS install-nudge banner isn't rendered for a signed-out visitor", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    # The bootstrap script (which references the id via getElementById, not
    # this attribute form) is always present — only the banner element
    # itself is gated on being signed in.
    refute html =~ "id=\"ios-install-banner\""
  end
end
