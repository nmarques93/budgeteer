# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :budgeteer, :scopes,
  user: [
    default: true,
    module: Budgeteer.Households.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Budgeteer.HouseholdsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :budgeteer,
  ecto_repos: [Budgeteer.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :budgeteer, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  repo: Budgeteer.Repo,
  queues: [statements: 5],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]

# Local-disk storage for uploaded statements (Phase 1/2). Revisit for S3
# when this app is actually deployed off a single host.
config :budgeteer, :statement_storage_path, Path.expand("priv/statements")

# Configure the endpoint
config :budgeteer, BudgeteerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BudgeteerWeb.ErrorHTML, json: BudgeteerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Budgeteer.PubSub,
  live_view: [signing_salt: "4vbdciqD"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :budgeteer, Budgeteer.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
