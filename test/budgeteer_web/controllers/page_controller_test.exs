defmodule BudgeteerWeb.PageControllerTest do
  use BudgeteerWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Your bank statement, turned into a ledger you can trust."
    assert html =~ ~p"/users/register"
  end
end
