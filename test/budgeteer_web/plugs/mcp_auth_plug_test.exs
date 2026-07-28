defmodule BudgeteerWeb.MCPAuthPlugTest do
  use BudgeteerWeb.ConnCase, async: true

  import Budgeteer.HouseholdsFixtures
  alias Budgeteer.Households
  alias BudgeteerWeb.MCPAuthPlug

  describe "call/2" do
    test "assigns :scope for a valid token", %{conn: conn} do
      user = user_fixture()
      {:ok, raw_token, _access_token} = Households.create_access_token(Households.Scope.for_user(user), "Test")

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> raw_token)
        |> MCPAuthPlug.call([])

      refute conn.halted
      assert conn.assigns.scope.user.id == user.id
    end

    test "halts with 401 when the authorization header is missing", %{conn: conn} do
      conn = MCPAuthPlug.call(conn, [])

      assert conn.halted
      assert conn.status == 401
      assert conn.resp_body =~ "unauthorized"
    end

    test "halts with 401 for a malformed token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer garbage")
        |> MCPAuthPlug.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 for a revoked token", %{conn: conn} do
      user = user_fixture()
      scope = Households.Scope.for_user(user)
      {:ok, raw_token, access_token} = Households.create_access_token(scope, "Test")
      {:ok, _} = Households.revoke_access_token(scope, access_token.id)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> raw_token)
        |> MCPAuthPlug.call([])

      assert conn.halted
      assert conn.status == 401
    end
  end
end
