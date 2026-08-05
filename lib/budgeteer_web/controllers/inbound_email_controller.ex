defmodule BudgeteerWeb.InboundEmailController do
  use BudgeteerWeb, :controller

  require Logger

  alias Budgeteer.Ledger
  alias Budgeteer.Statements
  alias Budgeteer.Statements.FileValidation
  alias Budgeteer.Statements.ResendWebhookSignature
  alias Budgeteer.RateLimit

  # Generous but not unlimited — this endpoint has no login to throttle,
  # so the only real abuse vector is spamming a guessed/leaked inbound
  # token with junk. Keyed by account, not source IP, since Resend's own
  # webhook IPs are shared across every customer's inbound traffic.
  @rate_limit_scale :timer.hours(1)
  @rate_limit_count 10

  @doc """
  Receives Resend's `email.received` webhook. Always responds 200 once
  the signature checks out, regardless of what happens after — Resend
  retries on anything else, and there's nothing to gain from a retry on
  "no matching account" or "attachment wasn't a real statement file."
  Only a bad signature gets a real error status, since that's the one
  case genuinely worth rejecting outright.
  """
  def create(conn, params) do
    with {:ok, secret} <- webhook_secret(),
         true <- ResendWebhookSignature.valid?(header_map(conn), raw_body(conn), secret) do
      handle_event(params)
      send_resp(conn, 200, "")
    else
      _ ->
        Logger.warning("Rejected inbound-email webhook: invalid or missing signature")
        send_resp(conn, 401, "")
    end
  end

  defp webhook_secret do
    case Application.get_env(:budgeteer, :resend_webhook_secret) do
      secret when is_binary(secret) and secret != "" -> {:ok, secret}
      _ -> :error
    end
  end

  defp header_map(conn), do: Map.new(conn.req_headers)
  defp raw_body(conn), do: conn.assigns[:raw_body] || ""

  defp handle_event(%{"type" => "email.received", "data" => data}) do
    with {:ok, account} <- resolve_account(data["to"]),
         :ok <- RateLimit.check("inbound-statement:#{account.id}", @rate_limit_scale, @rate_limit_count) do
      data
      |> Map.get("attachments", [])
      |> Enum.each(&process_attachment(&1, data["email_id"], account))
    else
      :error ->
        Logger.info("Inbound email at an unrecognized address — dropped")

      {:error, :rate_limited} ->
        Logger.warning("Inbound-statement rate limit hit for an account — dropped")
    end
  end

  defp handle_event(_other), do: :ok

  # The address is "stmt-<token>@<inbound domain>" — see
  # Account.generate_inbound_email_token/0 for how the token itself is
  # generated, and AccountLive.Show for where the household sees the
  # full address to give their bank / set up a forwarding rule with.
  defp resolve_account([to | _rest]) when is_binary(to) do
    with [local, _domain] <- String.split(to, "@", parts: 2),
         token <- String.replace_prefix(local, "stmt-", ""),
         %Ledger.Account{} = account <- Ledger.get_account_by_inbound_token(token) do
      {:ok, account}
    else
      _ -> :error
    end
  end

  defp resolve_account(_to), do: :error

  defp process_attachment(%{"id" => attachment_id, "filename" => filename}, email_id, account)
       when is_binary(attachment_id) and is_binary(filename) and is_binary(email_id) do
    ext = filename |> Path.extname() |> String.downcase()

    with true <- FileValidation.allowed_extension?(ext),
         {:ok, %{bytes: bytes}} <- resend_inbound_client().fetch_attachment(email_id, attachment_id),
         true <- byte_size(bytes) <= FileValidation.max_file_size(),
         true <- FileValidation.matches_magic_bytes?(ext, bytes) do
      save_statement(account, filename, ext, bytes)
    else
      {:error, reason} ->
        Logger.warning("Failed to fetch an inbound-statement attachment: #{inspect(reason)}")

      false ->
        Logger.info("Inbound-statement attachment failed validation (extension/size/content)")
    end
  end

  defp process_attachment(_attachment, _email_id, _account), do: :ok

  defp save_statement(account, filename, ext, bytes) do
    file_hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    storage_dir =
      Path.join(Application.fetch_env!(:budgeteer, :statement_storage_path), account.id)

    File.mkdir_p!(storage_dir)
    storage_path = Path.join(storage_dir, file_hash <> ext)
    file_preexisted? = File.exists?(storage_path)
    File.write!(storage_path, Budgeteer.Vault.encrypt!(bytes))

    attrs = %{
      "filename" => filename,
      "storage_path" => storage_path,
      "file_hash" => file_hash,
      "account_id" => account.id
    }

    case Statements.create_statement_from_email(account, attrs) do
      {:ok, _statement} ->
        :ok

      {:error, changeset} ->
        if not file_preexisted?, do: File.rm(storage_path)

        Logger.info("Inbound-statement create failed: #{inspect(changeset.errors)}")
    end
  end

  defp resend_inbound_client,
    do:
      Application.get_env(
        :budgeteer,
        :resend_inbound_client,
        Budgeteer.Statements.ResendInboundClient
      )
end
