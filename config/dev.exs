import Config

# Configure your database
config :budgeteer, Budgeteer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "budgeteer_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :budgeteer, BudgeteerWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}],
  # PWA install/service-worker testing doesn't strictly need this locally —
  # browsers treat localhost as a secure context over plain HTTP too — but
  # this mirrors what a real deployment needs and gives an HTTPS origin to
  # test against if ever needed. Self-signed cert from `mix phx.gen.cert`.
  https: [
    ip: {127, 0, 0, 1},
    port: 4001,
    cipher_suite: :strong,
    certfile: "priv/cert/selfsigned.pem",
    keyfile: "priv/cert/selfsigned_key.pem"
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "0xA/GONGlbE9pGaGGGEHnDQcn6x19+1C+KllB3mI8i46eFQ4COuFkqt0McS0ot0O",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:budgeteer, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:budgeteer, ~w(--watch)]}
  ]

# Enable dev routes for dashboard and mailbox
config :budgeteer, dev_routes: true

# Fixed dev-only Cloak key, same "baked-in default, prod requires env var"
# pattern as secret_key_base above. Never used for real data.
config :budgeteer, :cloak_key, "AfoPz51lh3S7kBOmygrj18YEqRmpHOtOXLx65mz9M+M="

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
