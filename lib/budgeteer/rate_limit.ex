defmodule Budgeteer.RateLimit do
  @moduledoc """
  Shared throttle for auth-adjacent actions that previously had no rate
  limiting at all: password/magic-link login, magic-link and household
  invite email requests, personal access token creation, and the MCP
  bearer-token auth plug. ETS-backed — this app runs a single Fly node,
  so no distributed backend (Redis, Mnesia) is needed.
  """
  use Hammer, backend: :ets

  @doc """
  Checks and increments the bucket for `key`. Returns `:ok` while under
  `limit` hits within `scale_ms`, or `{:error, :rate_limited}` once
  exceeded.
  """
  def check(key, scale_ms, limit) do
    case hit(key, scale_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, _retry_after_ms} -> {:error, :rate_limited}
    end
  end
end
