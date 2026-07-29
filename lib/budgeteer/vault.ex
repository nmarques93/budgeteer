defmodule Budgeteer.Vault do
  @moduledoc """
  Cloak vault for field-level encryption at rest. Currently used for
  `Statement.raw_ai_output` (bank statement data from AI parsing) — see
  CLAUDE.md's Decisions section for why this exists and what it covers.
  """
  use Cloak.Vault, otp_app: :budgeteer

  @impl GenServer
  def init(config) do
    config = Keyword.put(config, :ciphers, ciphers())
    {:ok, config}
  end

  defp ciphers do
    key = Application.fetch_env!(:budgeteer, :cloak_key)
    [default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(key)}]
  end
end
