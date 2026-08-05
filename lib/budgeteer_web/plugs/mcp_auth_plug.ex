defmodule BudgeteerWeb.MCPAuthPlug do
  @moduledoc """
  Authenticates MCP requests via a personal access token in the
  `authorization: Bearer <token>` header, and assigns `:scope` — which
  `Anubis.Server.Frame.assigns` inherits from `Plug.Conn.assigns` for HTTP
  transports, so every tool's `execute/2` reads `frame.assigns.scope`.

  This is a JSON API, not a browser page — an invalid token halts with a
  plain JSON 401, not an HTML error page or redirect.

  Requests are throttled per source IP before the token is even checked —
  this endpoint previously had no throttling at all, meaning a leaked or
  guessed bearer token had no cost-of-attempt backstop. The limit is
  generous (an MCP client can legitimately fire several tool calls in a
  handshake) but still caps brute-force speed.
  """

  import Plug.Conn

  alias Budgeteer.Households
  alias Budgeteer.RateLimit

  @scale :timer.minutes(1)
  @limit 60

  def init(opts), do: opts

  def call(conn, _opts) do
    if RateLimit.check("mcp:#{ip_string(conn)}", @scale, @limit) == :ok do
      authenticate(conn)
    else
      too_many_requests(conn)
    end
  end

  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {%Households.User{} = user, access_token} <-
           Households.get_user_and_access_token_by_access_token(token) do
      conn
      |> assign(:scope, Households.Scope.for_user(user))
      |> assign(:access_token, access_token)
    else
      _ -> unauthorized(conn)
    end
  end

  defp ip_string(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end

  defp too_many_requests(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(429, Jason.encode!(%{error: "rate_limited"}))
    |> halt()
  end
end
