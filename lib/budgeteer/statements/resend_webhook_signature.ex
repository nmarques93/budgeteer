defmodule Budgeteer.Statements.ResendWebhookSignature do
  @moduledoc """
  Verifies a Resend inbound-email webhook's signature — Resend builds its
  webhook infrastructure on Svix, and their own docs defer to Svix's
  verification scheme rather than documenting it themselves, so this
  implements Svix's algorithm directly (no SDK): HMAC-SHA256 over
  `"{svix-id}.{svix-timestamp}.{raw body}"`, keyed by the base64-decoded
  secret (after stripping its `whsec_` prefix), checked against the
  space-separated `v1,<base64>` entries in the `svix-signature` header.

  Pure/deterministic — no network call — so unlike the API-calling
  clients in this app, this isn't behind a Mox-mockable behaviour; it's
  tested directly against real (and forged) signatures.
  """

  # Svix's own recommended tolerance, to reject a replayed webhook whose
  # timestamp is stale.
  @tolerance_seconds 300

  @doc """
  `headers` is a map with "svix-id"/"svix-timestamp"/"svix-signature"
  string keys, as read off the raw request. `raw_body` must be the
  *exact* bytes Resend sent — re-serializing parsed JSON would produce a
  different signature than the one Resend computed.
  """
  def valid?(headers, raw_body, secret)
      when is_map(headers) and is_binary(raw_body) and is_binary(secret) do
    with {:ok, id} <- fetch_header(headers, "svix-id"),
         {:ok, timestamp} <- fetch_header(headers, "svix-timestamp"),
         {:ok, signature_header} <- fetch_header(headers, "svix-signature"),
         true <- fresh?(timestamp) do
      expected = sign(id, timestamp, raw_body, secret)

      signature_header
      |> String.split(" ", trim: true)
      |> Enum.any?(&matches?(&1, expected))
    else
      _ -> false
    end
  end

  defp fetch_header(headers, key) do
    case Map.fetch(headers, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> :error
    end
  end

  defp fresh?(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {timestamp, ""} -> abs(System.system_time(:second) - timestamp) <= @tolerance_seconds
      _ -> false
    end
  end

  defp sign(id, timestamp, raw_body, secret) do
    key = secret |> String.replace_prefix("whsec_", "") |> Base.decode64!()
    signed_content = id <> "." <> timestamp <> "." <> raw_body

    :hmac
    |> :crypto.mac(:sha256, key, signed_content)
    |> Base.encode64()
  end

  defp matches?("v1," <> candidate, expected), do: Plug.Crypto.secure_compare(candidate, expected)
  defp matches?(_other, _expected), do: false
end
