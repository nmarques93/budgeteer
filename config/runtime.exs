import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/budgeteer start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :budgeteer, BudgeteerWeb.Endpoint, server: true
end

config :budgeteer, BudgeteerWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Read in dev/prod once the user sets the env var. Unconfigured in test —
# the AI client is mocked there (see config/test.exs).
config :budgeteer, :anthropic_api_key, System.get_env("ANTHROPIC_API_KEY")

# DeepSeek — cheaper model used only for Budgeteer.Insights (budget
# insights are a summarization task over already-computed numbers, not
# document extraction, so they don't need Claude's accuracy/cost). Same
# unconditional-read tolerance as ANTHROPIC_API_KEY above.
config :budgeteer, :deepseek_api_key, System.get_env("DEEPSEEK_API_KEY")

# Google OAuth. Same tolerance as ANTHROPIC_API_KEY above — unconditional,
# no raise if unset — rather than the RESEND_API_KEY raise-in-prod-only
# pattern, since this needs to be testable via a real browser flow in dev
# once set locally, and should degrade gracefully (the button just won't
# work) rather than crash boot. Register a redirect URI of
# "<host>/auth/google/callback" in Google Cloud Console to get these.
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

# Error tracking. Same tolerance as ANTHROPIC_API_KEY/GOOGLE_CLIENT_ID above —
# unset means Sentry's client just no-ops rather than crashing boot.
config :sentry, dsn: System.get_env("SENTRY_DSN")

# Push notifications (native iOS app, see mobile/) via APNs. Same
# unconditional-read tolerance as the credentials above — Budgeteer.Push
# no-ops when any of these are unset, so the app works fully without them
# (push is additive to the existing email notification path, never a
# dependency of it). APNS_KEY is the raw contents of the .p8 Auth Key file
# downloaded once from the Apple Developer portal (Certificates, IDs &
# Profiles > Keys); APNS_KEY_ID and APNS_TEAM_ID come from that same
# portal. APNS_TOPIC is the app's bundle id (see mobile/capacitor.config.json).
config :budgeteer, Budgeteer.Push,
  apns_key: System.get_env("APNS_KEY"),
  apns_key_id: System.get_env("APNS_KEY_ID"),
  apns_team_id: System.get_env("APNS_TEAM_ID"),
  apns_topic: System.get_env("APNS_TOPIC", "com.budgeteer.app")

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :budgeteer, BudgeteerWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/budgeteer_web/router\.ex$"E,
        ~r"lib/budgeteer_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :budgeteer, Budgeteer.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :budgeteer, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :budgeteer, BudgeteerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :budgeteer, BudgeteerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :budgeteer, BudgeteerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Resend — chosen over Mailgun/SES because there's no sandbox/recipient-
  # verification step blocking real invite emails from day one. Already
  # bundled in the swoosh dependency (Swoosh.Adapters.Resend), and the Req
  # API client is configured at compile time in config/prod.exs.
  resend_api_key =
    System.get_env("RESEND_API_KEY") ||
      raise """
      environment variable RESEND_API_KEY is missing.
      Sign up at https://resend.com and create an API key.
      """

  config :budgeteer, Budgeteer.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: resend_api_key

  # Encrypts `Statement.raw_ai_output` at rest (real bank statement data) —
  # see Budgeteer.Vault / Budgeteer.Encrypted.Map and CLAUDE.md's Decisions
  # section. Generate with:
  #   mix run -e 'IO.puts(:crypto.strong_rand_bytes(32) |> Base.encode64())'
  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one by calling:
          mix run -e 'IO.puts(:crypto.strong_rand_bytes(32) |> Base.encode64())'
      """

  config :budgeteer, :cloak_key, cloak_key

  # Only set during an active key rotation — see Budgeteer.Vault's
  # moduledoc for the rotation runbook. Unset the rest of the time.
  if previous_key = System.get_env("CLOAK_PREVIOUS_KEY") do
    config :budgeteer, :cloak_previous_key, previous_key
  end

  # Statement uploads on disk. Defaults to the compile-time priv/statements
  # path (config/config.exs) for a single persistent-disk deployment; set
  # this to a mounted volume's path (e.g. a Fly.io volume) to keep uploads
  # across deploys/restarts. See CLAUDE.md's Decisions section.
  if storage_path = System.get_env("STATEMENT_STORAGE_PATH") do
    config :budgeteer, :statement_storage_path, storage_path
  end

  # Recipe images on disk — same reasoning as STATEMENT_STORAGE_PATH above,
  # point this at a subdirectory of the same mounted volume.
  if recipe_image_storage_path = System.get_env("RECIPE_IMAGE_STORAGE_PATH") do
    config :budgeteer, :recipe_image_storage_path, recipe_image_storage_path
  end
end
