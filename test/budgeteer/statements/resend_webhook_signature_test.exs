defmodule Budgeteer.Statements.ResendWebhookSignatureTest do
  use ExUnit.Case, async: true

  alias Budgeteer.Statements.ResendWebhookSignature

  @secret "whsec_dGVzdC1zZWNyZXQta2V5LWZvci1zaWduaW5n"

  defp sign(id, timestamp, body, secret \\ @secret) do
    key = secret |> String.replace_prefix("whsec_", "") |> Base.decode64!()
    signed_content = id <> "." <> timestamp <> "." <> body

    :hmac
    |> :crypto.mac(:sha256, key, signed_content)
    |> Base.encode64()
  end

  defp headers(id, timestamp, signature) do
    %{"svix-id" => id, "svix-timestamp" => timestamp, "svix-signature" => "v1,#{signature}"}
  end

  test "accepts a genuinely valid signature" do
    id = "msg_test123"
    timestamp = Integer.to_string(System.system_time(:second))
    body = ~s({"type":"email.received"})
    signature = sign(id, timestamp, body)

    assert ResendWebhookSignature.valid?(headers(id, timestamp, signature), body, @secret)
  end

  test "rejects a signature computed with the wrong secret" do
    id = "msg_test123"
    timestamp = Integer.to_string(System.system_time(:second))
    body = ~s({"type":"email.received"})
    signature = sign(id, timestamp, body, "whsec_" <> Base.encode64("a-different-secret"))

    refute ResendWebhookSignature.valid?(headers(id, timestamp, signature), body, @secret)
  end

  test "rejects when the body was tampered with after signing" do
    id = "msg_test123"
    timestamp = Integer.to_string(System.system_time(:second))
    body = ~s({"type":"email.received"})
    signature = sign(id, timestamp, body)

    refute ResendWebhookSignature.valid?(
             headers(id, timestamp, signature),
             ~s({"type":"something.else"}),
             @secret
           )
  end

  test "rejects a stale timestamp (outside the tolerance window)" do
    id = "msg_test123"
    stale_timestamp = Integer.to_string(System.system_time(:second) - 600)
    body = ~s({"type":"email.received"})
    signature = sign(id, stale_timestamp, body)

    refute ResendWebhookSignature.valid?(
             headers(id, stale_timestamp, signature),
             body,
             @secret
           )
  end

  test "rejects when a required header is missing" do
    body = ~s({"type":"email.received"})
    headers = %{"svix-id" => "msg_test123", "svix-timestamp" => "123"}

    refute ResendWebhookSignature.valid?(headers, body, @secret)
  end

  test "accepts when the matching signature is one of several space-separated entries" do
    id = "msg_test123"
    timestamp = Integer.to_string(System.system_time(:second))
    body = ~s({"type":"email.received"})
    signature = sign(id, timestamp, body)
    headers = headers(id, timestamp, "v1,bogus " <> "v1,#{signature}")

    assert ResendWebhookSignature.valid?(headers, body, @secret)
  end
end
