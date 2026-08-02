defmodule Budgeteer.PushTest do
  use ExUnit.Case, async: true

  alias Budgeteer.Push

  describe "send/2" do
    test "no-ops when APNs isn't configured" do
      # Test env never sets :apns_key/:apns_key_id/:apns_team_id/:apns_topic
      # (see config/runtime.exs) — same "graceful no-op when unconfigured"
      # contract as every other optional external integration in this app.
      assert Push.send("some-device-token", %{title: "Hi", body: "Body"}) == {:ok, :skipped}
    end
  end

  describe "der_to_raw_signature/1" do
    test "converts a DER ECDSA signature into a verifiable raw 64-byte r||s signature" do
      # This is the one genuinely tricky piece of hand-rolling an ES256 JWT
      # without jose/joken: :public_key.sign/3 returns DER, but JWS needs
      # raw r||s. Verified here against a throwaway P-256 key rather than a
      # real Apple key (none available), but this proves the conversion
      # math itself is correct, independent of ever reaching Apple's servers.
      {public_key, private_key_der} = :crypto.generate_key(:ecdh, :secp256r1)

      ec_private_key =
        {:ECPrivateKey, 1, private_key_der, {:namedCurve, {1, 2, 840, 10045, 3, 1, 7}}, public_key,
         :asn1_NOVALUE}

      signing_input = "header.claims"
      der_signature = :public_key.sign(signing_input, :sha256, ec_private_key)

      raw_signature = Push.der_to_raw_signature(der_signature)
      assert byte_size(raw_signature) == 64

      <<r_bytes::binary-32, s_bytes::binary-32>> = raw_signature
      r = :binary.decode_unsigned(r_bytes)
      s = :binary.decode_unsigned(s_bytes)
      rebuilt_der = :public_key.der_encode(:"ECDSA-Sig-Value", {:"ECDSA-Sig-Value", r, s})

      params = {:namedCurve, {1, 2, 840, 10045, 3, 1, 7}}

      assert :public_key.verify(signing_input, :sha256, rebuilt_der, {{:ECPoint, public_key}, params})
    end
  end

  describe "PEM parsing (Apple's .p8 key format)" do
    test ":public_key can load and sign with a PKCS8 EC private key" do
      # Apple's downloaded .p8 Auth Key is exactly this format
      # ("-----BEGIN PRIVATE KEY-----", PKCS8-wrapped EC key) — confirms
      # Budgeteer.Push's pem_decode/pem_entry_decode pair (used in the
      # private build_jwt/1) needs no special-casing to handle it.
      {:ok, pem} = generate_pkcs8_ec_pem()

      [pem_entry] = :public_key.pem_decode(pem)
      assert elem(pem_entry, 0) == :PrivateKeyInfo

      decoded = :public_key.pem_entry_decode(pem_entry)
      assert elem(decoded, 0) == :ECPrivateKey

      signature = :public_key.sign("some signing input", :sha256, decoded)
      assert is_binary(signature)
    end

    defp generate_pkcs8_ec_pem do
      with openssl when not is_nil(openssl) <- System.find_executable("openssl"),
           {ec_key_pem, 0} <- System.cmd(openssl, ~w(ecparam -genkey -name prime256v1 -noout)) do
        path = Path.join(System.tmp_dir!(), "push_test_ec_key_#{System.unique_integer()}.pem")
        File.write!(path, ec_key_pem)

        try do
          {pkcs8_pem, 0} = System.cmd(openssl, ~w(pkcs8 -topk8 -nocrypt -in #{path}))
          {:ok, pkcs8_pem}
        after
          File.rm(path)
        end
      else
        _ -> {:error, :openssl_unavailable}
      end
    end
  end
end
