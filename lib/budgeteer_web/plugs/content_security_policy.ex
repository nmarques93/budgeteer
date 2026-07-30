defmodule BudgeteerWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sets a Content-Security-Policy header, replacing `put_secure_browser_headers`'s
  minimal default (`base-uri`/`frame-ancestors` only). No template in this
  app uses `raw`/unescaped HTML, but a CSP is defense-in-depth against any
  future XSS sink, not a substitute for escaping.

  `script-src` uses a per-request nonce rather than `'unsafe-inline'` — the
  only inline script in the app is the theme-toggle bootstrap in
  `root.html.heex`, which reads the nonce off `@csp_nonce`. `style-src`
  keeps `'unsafe-inline'` since Tailwind-generated markup relies on inline
  `style=""` attributes in a few places; that's a much smaller blast radius
  than allowing inline `<script>`. `connect-src` includes `ws:`/`wss:`
  explicitly (rather than relying on `'self'`'s same-origin scheme-upgrade
  matching) so the LiveView socket isn't at the mercy of a browser that
  doesn't implement that CSP3 behavior.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = generate_nonce()

    conn
    |> assign(:csp_nonce, nonce)
    |> Phoenix.Controller.put_secure_browser_headers(%{
      "content-security-policy" => build_csp(nonce)
    })
  end

  defp generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end

  defp build_csp(nonce) do
    [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{nonce}'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data:",
      "font-src 'self'",
      "connect-src 'self' ws: wss:",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'self'",
      "object-src 'none'"
    ]
    |> Enum.join("; ")
  end
end
