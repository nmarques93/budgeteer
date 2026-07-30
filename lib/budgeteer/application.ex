defmodule Budgeteer.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Bandit (this app's adapter) doesn't need Sentry.PlugCapture — that
    # plug exists only to rescue exceptions Cowboy would otherwise swallow.
    # Sentry.LoggerHandler's default excluded_domains ([:cowboy, :bandit])
    # assumes PlugCapture is handling those, so without it we'd silently
    # drop every crash — override to capture everything instead.
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{capture_log_messages: true, capture_excluded_domains: []}
    })

    children = [
      BudgeteerWeb.Telemetry,
      Budgeteer.Repo,
      Budgeteer.Vault,
      {Budgeteer.RateLimit, clean_period: :timer.minutes(10)},
      {DNSCluster, query: Application.get_env(:budgeteer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Budgeteer.PubSub},
      BudgeteerWeb.Presence,
      {Oban, Application.fetch_env!(:budgeteer, Oban)},
      {BudgeteerWeb.MCP.Server, transport: :streamable_http},
      # Start to serve requests, typically the last entry
      BudgeteerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Budgeteer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BudgeteerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
