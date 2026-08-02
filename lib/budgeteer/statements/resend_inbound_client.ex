defmodule Budgeteer.Statements.ResendInboundClient do
  @moduledoc """
  Fetches inbound-email attachment content from Resend's Receiving API.
  The `email.received` webhook only carries attachment *metadata* (id,
  filename, content_type) — the actual bytes need two follow-up calls:
  one to get a short-lived `download_url`, then a plain GET against that
  URL. Elixir has no official Resend SDK, so this is raw HTTP via `Req`,
  same pattern as the Anthropic/DeepSeek clients.
  """

  @behaviour Budgeteer.Statements.ResendInboundClientBehaviour

  @api_url "https://api.resend.com"

  @impl true
  def fetch_attachment(email_id, attachment_id)
      when is_binary(email_id) and is_binary(attachment_id) do
    with {:ok, metadata} <- get_attachment_metadata(email_id, attachment_id),
         %{"filename" => filename, "content_type" => content_type, "download_url" => url} <-
           metadata,
         {:ok, bytes} <- download(url) do
      {:ok, %{filename: filename, content_type: content_type, bytes: bytes}}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_metadata, other}}
    end
  end

  defp get_attachment_metadata(email_id, attachment_id) do
    url = "#{@api_url}/emails/receiving/#{email_id}/attachments/#{attachment_id}"

    case Req.get(url, headers: headers(), receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  # No auth header here — download_url is itself a signed, short-lived
  # link, and decode_body: false guarantees the exact original bytes
  # regardless of the attachment's content-type (matches
  # RecipeUrlFetcher's same deliberate choice).
  defp download(url) do
    case Req.get(url, receive_timeout: 60_000, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: bytes}} -> {:ok, bytes}
      {:ok, %Req.Response{status: status}} -> {:error, {:download_failed, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp headers, do: [{"authorization", "Bearer " <> (api_key() || "")}]

  defp api_key, do: Application.fetch_env!(:budgeteer, :resend_api_key)
end
