defmodule Budgeteer.AI.Client do
  @moduledoc """
  Calls the Claude Messages API to extract transactions from a bank
  statement (PDF or image). Elixir has no official Anthropic SDK, so this
  is raw HTTP via `Req`. Uses structured outputs (`output_config.format`)
  so a successful response is guaranteed-valid JSON rather than relying on
  a "return only JSON" prompt convention.
  """

  @behaviour Budgeteer.AI.ClientBehaviour

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-5"
  @anthropic_version "2023-06-01"

  @system_prompt """
  You are a bank statement parser. Extract every transaction from the
  provided bank statement. Do not invent transactions — only extract what
  is explicitly present. amount_cents is always an integer number of cents:
  debits (money leaving the account) are negative, credits are positive.

  For each transaction, also set `category` to the best-matching category
  from the household's existing categories (given below), copying its name
  exactly. If none of the existing categories fit well, suggest a new,
  concise category name instead (e.g. "Restaurants"). If you have no basis
  to guess, use an empty string.
  """

  @output_schema %{
    "type" => "object",
    "properties" => %{
      "currency" => %{"type" => "string", "description" => "ISO 4217 currency code, e.g. EUR"},
      "transactions" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "date" => %{"type" => "string", "description" => "ISO 8601 date, YYYY-MM-DD"},
            "amount_cents" => %{"type" => "integer"},
            "merchant" => %{"type" => "string"},
            "description" => %{"type" => "string"},
            "category" => %{
              "type" => "string",
              "description" => "Best-matching existing category name, a newly suggested one, or empty string"
            }
          },
          "required" => ["date", "amount_cents", "merchant", "description", "category"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["currency", "transactions"],
    "additionalProperties" => false
  }

  @impl true
  def parse_statement(file_bytes, media_type, category_names)
      when is_binary(file_bytes) and is_binary(media_type) and is_list(category_names) do
    body = %{
      model: @model,
      max_tokens: 8000,
      system: @system_prompt <> "\n\n" <> categories_hint(category_names),
      output_config: %{format: %{type: "json_schema", schema: @output_schema}},
      messages: [
        %{
          role: "user",
          content: [
            document_block(file_bytes, media_type),
            %{type: "text", text: "Extract all transactions from this bank statement."}
          ]
        }
      ]
    }

    # Req's default receive_timeout is 15s — too tight for a real multi-page
    # document analysis (structured extraction over several pages can easily
    # take longer than that, especially on a cold prompt cache).
    case Req.post(@api_url, json: body, headers: headers(), receive_timeout: 120_000) do
      {:ok, %Req.Response{status: 200, body: response_body}} -> handle_success(response_body)
      {:ok, %Req.Response{status: status, body: response_body}} -> {:error, {:http_error, status, response_body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp categories_hint([]), do: "This household has no existing categories yet — suggest reasonable new ones."

  defp categories_hint(category_names) do
    "This household's existing categories are: " <> Enum.join(category_names, ", ")
  end

  defp document_block(file_bytes, media_type) do
    %{
      type: "document",
      source: %{
        type: "base64",
        media_type: media_type,
        data: Base.encode64(file_bytes)
      }
    }
  end

  defp headers do
    [
      {"x-api-key", api_key()},
      {"anthropic-version", @anthropic_version},
      {"content-type", "application/json"}
    ]
  end

  defp api_key, do: Application.fetch_env!(:budgeteer, :anthropic_api_key)

  defp handle_success(%{"stop_reason" => "refusal"} = body) do
    {:error, {:refusal, get_in(body, ["stop_details"]) || body}}
  end

  defp handle_success(%{"content" => content}) do
    case Enum.find(content, &(&1["type"] == "text")) do
      %{"text" => text} ->
        case Jason.decode(text) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      nil ->
        {:error, {:no_text_block, content}}
    end
  end

  defp handle_success(body), do: {:error, {:unexpected_response, body}}
end
