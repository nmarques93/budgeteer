defmodule BudgeteerWeb.HealthController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Repo

  @doc """
  Cheap process liveness check. This deliberately does not query the database.
  """
  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  @doc """
  Readiness check for traffic that needs the database.
  """
  def ready(conn, _params) do
    case Repo.query("SELECT 1") do
      {:ok, _result} -> json(conn, %{status: "ok"})
      {:error, _reason} -> conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  end
end
