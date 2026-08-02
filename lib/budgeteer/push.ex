defmodule Budgeteer.Push do
  @moduledoc """
  Sends push notifications to registered iOS devices (see
  `Households.DeviceToken`) via Apple's APNs HTTP/2 provider API, using a
  JWT signed with the account's APNs Auth Key — a token-based `.p8` key
  scoped to the whole Apple Developer team, not a per-app certificate.

  Reads `:apns_key` / `:apns_key_id` / `:apns_team_id` / `:apns_topic`
  from `Application.get_env(:budgeteer, __MODULE__)`, set via
  `APNS_KEY`/`APNS_KEY_ID`/`APNS_TEAM_ID` in `config/runtime.exs` — same
  "unset = graceful no-op" tolerance as `ANTHROPIC_API_KEY`/
  `GOOGLE_CLIENT_ID` (see CLAUDE.md): `send/2` returns `{:ok, :skipped}`
  immediately when unconfigured, and every call is wrapped in a rescue so
  a push failure can never propagate to its caller. This matters because
  the only caller, `Ledger.BudgetAlertWorker`, already has a
  proven-working notification path (email) — push is additive, and must
  never be able to break that.

  **The JWT-signing math here (ES256, including the DER → raw r‖s
  signature conversion `:public_key.sign/3` requires for JWS) was verified
  directly** — signed and round-tripped through `:public_key.verify/4`
  against a throwaway P‑256 key, and separately confirmed that
  `:public_key.pem_entry_decode/1` correctly unwraps a PKCS8 `.p8`-style
  `"-----BEGIN PRIVATE KEY-----"` PEM (Apple's actual key format) down to
  a signable `ECPrivateKey` with no special-casing needed. **What's NOT
  verified is an actual call against Apple's servers** — that needs a
  real Auth Key from an Apple Developer account, which wasn't available
  here. Confirm a real send succeeds once real credentials exist.
  """

  require Logger

  @apns_host "api.push.apple.com"

  @doc """
  Sends a push notification (`%{title:, body:}`) to one device token.
  Always returns `:ok` — including `{:ok, :skipped}` when APNs isn't
  configured, or when the send itself fails; see the moduledoc for why
  failures are swallowed here rather than propagated.
  """
  def send(device_token, %{title: _title, body: _body} = notification) do
    case config() do
      {:ok, config} -> do_send(device_token, notification, config)
      :not_configured -> {:ok, :skipped}
    end
  rescue
    error ->
      Logger.warning(
        "Budgeteer.Push send failed: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      {:ok, :skipped}
  end

  defp config do
    env = Application.get_env(:budgeteer, __MODULE__, [])

    with key_pem when is_binary(key_pem) and key_pem != "" <- Keyword.get(env, :apns_key),
         key_id when is_binary(key_id) and key_id != "" <- Keyword.get(env, :apns_key_id),
         team_id when is_binary(team_id) and team_id != "" <- Keyword.get(env, :apns_team_id),
         topic when is_binary(topic) and topic != "" <- Keyword.get(env, :apns_topic) do
      {:ok, %{key_pem: key_pem, key_id: key_id, team_id: team_id, topic: topic}}
    else
      _ -> :not_configured
    end
  end

  defp do_send(device_token, %{title: title, body: body}, config) do
    jwt = build_jwt(config)

    payload = %{
      "aps" => %{"alert" => %{"title" => title, "body" => body}, "sound" => "default"}
    }

    response =
      Req.post!(
        "https://#{@apns_host}/3/device/#{device_token}",
        headers: [
          {"authorization", "bearer #{jwt}"},
          {"apns-topic", config.topic},
          {"apns-push-type", "alert"}
        ],
        json: payload,
        connect_options: [protocols: [:http2]],
        retry: false
      )

    case response.status do
      200 -> :ok
      status -> {:error, {status, response.body}}
    end
  end

  # Builds the APNs provider JWT: header {alg: ES256, kid}, claims {iss:
  # team_id, iat: now}, signed with the .p8 key's EC private key.
  defp build_jwt(config) do
    header = %{"alg" => "ES256", "kid" => config.key_id}
    claims = %{"iss" => config.team_id, "iat" => System.system_time(:second)}

    header_b64 = header |> Jason.encode!() |> Base.url_encode64(padding: false)
    claims_b64 = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    signing_input = header_b64 <> "." <> claims_b64

    [pem_entry] = :public_key.pem_decode(config.key_pem)
    private_key = :public_key.pem_entry_decode(pem_entry)
    der_signature = :public_key.sign(signing_input, :sha256, private_key)

    signing_input <> "." <> Base.url_encode64(der_to_raw_signature(der_signature), padding: false)
  end

  # JWS's ES256 needs a raw 64-byte (r || s, each left-padded to 32 bytes)
  # P-256 signature, but :public_key.sign/3 returns a DER-encoded
  # ECDSA-Sig-Value — this is that conversion, done by hand rather than
  # pulling in jose/joken for one JWT. Public (not private) specifically so
  # it has a real regression test — see push_test.exs — rather than only
  # the one-off manual verification (sign → convert → round-trip through
  # :public_key.verify/4 against a throwaway key) that first confirmed this
  # was correct.
  @doc false
  def der_to_raw_signature(der) do
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)
    pad32(r) <> pad32(s)
  end

  defp pad32(int) do
    bin = :binary.encode_unsigned(int)
    :binary.copy(<<0>>, max(32 - byte_size(bin), 0)) <> bin
  end
end
