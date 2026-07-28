defmodule BudgeteerWeb.MCPAuthPlug do
  @moduledoc """
  Authenticates MCP requests via a personal access token in the
  `authorization: Bearer <token>` header, and assigns `:scope` — which
  `Anubis.Server.Frame.assigns` inherits from `Plug.Conn.assigns` for HTTP
  transports, so every tool's `execute/2` reads `frame.assigns.scope`.

  This is a JSON API, not a browser page — an invalid token halts with a
  plain JSON 401, not an HTML error page or redirect.
  """

  import Plug.Conn

  alias Budgeteer.Households

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Households.User{} = user <- Households.get_user_by_access_token(token) do
      assign(conn, :scope, Households.Scope.for_user(user))
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end
