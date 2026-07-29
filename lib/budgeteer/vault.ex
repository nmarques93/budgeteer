defmodule Budgeteer.Vault do
  @moduledoc """
  Cloak vault for field-level encryption at rest. Currently used for
  `Statement.raw_ai_output` (bank statement data from AI parsing) — see
  CLAUDE.md's Decisions section for why this exists and what it covers.

  Supports rotating `CLOAK_KEY` without destroying already-encrypted data:
  set `CLOAK_PREVIOUS_KEY` to the outgoing key alongside a new `CLOAK_KEY`,
  redeploy, and Cloak will keep decrypting old rows with the retired
  cipher (matched by its embedded tag) while every new write uses the new
  default. Once a background pass has re-saved (and so re-encrypted) every
  row under the new key, `CLOAK_PREVIOUS_KEY` can be removed. See
  CLAUDE.md's Decisions section for the full rotation runbook.
  """
  use Cloak.Vault, otp_app: :budgeteer

  @impl GenServer
  def init(config) do
    config = Keyword.put(config, :ciphers, ciphers())
    {:ok, config}
  end

  defp ciphers do
    key = Application.fetch_env!(:budgeteer, :cloak_key)

    default_cipher =
      {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(key)}

    case Application.get_env(:budgeteer, :cloak_previous_key) do
      nil ->
        [default: default_cipher]

      previous_key ->
        retired_cipher =
          {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V0", key: Base.decode64!(previous_key)}

        [default: default_cipher, retired: retired_cipher]
    end
  end
end
