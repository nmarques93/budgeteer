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

  If the document contains no identifiable transactions at all, return an
  empty `transactions` array. Never return a placeholder transaction with
  blank or zero fields just to have something in the array.
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
              "description" =>
                "Best-matching existing category name, a newly suggested one, or empty string"
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
      # `temperature` used to be pinned to 0 here for determinism, but this
      # model generation rejects the parameter outright (400: "temperature
      # is deprecated for this model") — caught as a real production
      # regression, not in dev, since dev has no API key to exercise this
      # against. `validate_parsed/1` below is what actually guards against
      # degenerate output now.
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
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        handle_success(response_body)

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @recipe_system_prompt """
  You are a recipe parser. Extract the recipe's name, its ingredients, and
  a `notes` field from the provided recipe (plain text, or an image/PDF of
  one, or text scraped from a recipe web page — which may include page
  chrome/ads/comments alongside the actual recipe; ignore anything that
  isn't part of the recipe itself). Do not invent ingredients — only
  extract what is explicitly present.

  `notes` should combine servings/prep/cook time (if stated) with a
  concise summary of the cooking instructions — condense multi-step
  instructions into a few sentences covering the key steps, not a
  verbatim copy of every step. If there are no instructions at all, just
  include whatever servings/timing info is present, or leave notes empty
  if there's genuinely nothing beyond the ingredient list.

  For each ingredient's quantity, use a plain numeric string (e.g. "2",
  "0.5") only when the recipe states a numeric amount. For a non-numeric
  or vague amount ("a pinch", "to taste", "a handful"), leave quantity as
  an empty string and put the descriptive amount in unit instead (e.g.
  unit: "pinch"). If no amount is given at all, leave both empty.
  """

  @recipe_output_schema %{
    "type" => "object",
    "properties" => %{
      "name" => %{"type" => "string"},
      "notes" => %{
        "type" => "string",
        "description" =>
          "Servings/timing if mentioned, plus a concise summary of the cooking instructions; empty string if none"
      },
      "ingredients" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "quantity" => %{
              "type" => "string",
              "description" => "A plain numeric amount if stated, else empty string"
            },
            "unit" => %{"type" => "string"}
          },
          "required" => ["name", "quantity", "unit"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["name", "notes", "ingredients"],
    "additionalProperties" => false
  }

  @impl true
  def parse_recipe({:text, text}) when is_binary(text) do
    request_recipe([
      %{type: "text", text: "Extract the recipe from the following text:\n\n" <> text}
    ])
  end

  def parse_recipe({:file, file_bytes, media_type})
      when is_binary(file_bytes) and is_binary(media_type) do
    request_recipe([
      document_block(file_bytes, media_type),
      %{type: "text", text: "Extract the recipe from this image/document."}
    ])
  end

  defp request_recipe(content_blocks) do
    body = %{
      model: @model,
      max_tokens: 4000,
      system: @recipe_system_prompt,
      output_config: %{format: %{type: "json_schema", schema: @recipe_output_schema}},
      messages: [%{role: "user", content: content_blocks}]
    }

    case Req.post(@api_url, json: body, headers: headers(), receive_timeout: 120_000) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        handle_success(response_body)

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp categories_hint([]),
    do: "This household has no existing categories yet — suggest reasonable new ones."

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
          {:ok, parsed} -> validate_parsed(parsed)
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      nil ->
        {:error, {:no_text_block, content}}
    end
  end

  defp handle_success(body), do: {:error, {:unexpected_response, body}}

  # A schema-valid but degenerate response (every field blank/zero on a
  # transaction) is worse than an outright error — treating it as a success
  # would let a placeholder row reach the review screen looking like real
  # data. An empty `transactions` list is a legitimate "nothing to extract"
  # result and is left alone; only a blank *entry* is rejected. Returning
  # `:error` here lets `ParseWorker`'s existing Oban retry take another pass
  # instead of the statement silently landing on a junk result.
  defp validate_parsed(%{"transactions" => transactions} = parsed) do
    if Enum.any?(transactions, &blank_transaction?/1) do
      {:error, {:degenerate_response, parsed}}
    else
      {:ok, parsed}
    end
  end

  defp validate_parsed(parsed), do: {:ok, parsed}

  defp blank_transaction?(t) do
    t["date"] == "" and t["merchant"] == "" and t["description"] == "" and t["amount_cents"] == 0
  end
end
