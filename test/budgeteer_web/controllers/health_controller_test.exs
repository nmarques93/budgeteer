defmodule BudgeteerWeb.HealthControllerTest do
  use BudgeteerWeb.ConnCase

  test "GET /health/live returns a liveness response", %{conn: conn} do
    assert %{"status" => "ok"} = conn |> get("/health/live") |> json_response(200)
  end

  test "GET /health/ready returns a database readiness response", %{conn: conn} do
    assert %{"status" => "ok"} = conn |> get("/health/ready") |> json_response(200)
  end
end
