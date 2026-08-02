defmodule BudgeteerWeb.Plugs.CacheBodyReader do
  @moduledoc """
  A `Plug.Parsers` `:body_reader` that stashes the raw request body into
  `conn.assigns.raw_body` before it's consumed by JSON parsing — needed
  to verify the inbound-statement-email webhook's signature, which is
  computed over the *exact* bytes Resend sent, not a re-serialized
  version of the parsed JSON (standard Phoenix pattern for this exact
  problem — any webhook signed the Stripe/Svix way needs the same thing).
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    existing = conn.assigns[:raw_body] || ""
    {:ok, body, Plug.Conn.assign(conn, :raw_body, existing <> body)}
  end
end
