defmodule Budgeteer.AI.DeepSeekClient do
  @moduledoc """
  Calls DeepSeek's chat completions API (OpenAI-compatible) — the
  text-only AI backend for this app. Deliberately a separate, cheaper
  model from `Budgeteer.AI.Client` (Anthropic): budget insights (spotting
  "this is worth mentioning" in a small pre-computed JSON summary) and
  recipe parsing from plain text are both good-enough-model tasks, not
  document-extraction ones, so they don't need Claude's accuracy or cost.
  Confirmed directly against the real API that DeepSeek's chat endpoint
  rejects image/document content outright — this client must never be
  used for a task that needs to *see* a file; that stays on
  `Budgeteer.AI.Client`. Elixir has no official DeepSeek SDK, so this is
  raw HTTP via `Req`, same as the Anthropic client.
  """

  @behaviour Budgeteer.AI.DeepSeekClientBehaviour

  @api_url "https://api.deepseek.com/chat/completions"
  @model "deepseek-chat"

  @insights_system_prompt """
  You are a household budgeting assistant. Given a household's spending
  data as JSON, identify 2 to 4 genuinely notable observations — things
  worth a household member's attention, not generic restatements of the
  numbers. Good examples: pacing meaningfully over or under a category's
  usual spend, a category newly at or over its budget, a clear balance
  trend. Skip anything unremarkable — if nothing stands out, return fewer
  insights rather than padding with filler. A category with no
  "usual_monthly_spend" has no history yet — don't make a pacing claim
  about it. Each insight is one concise sentence, plain language, no
  jargon, written directly to the household (e.g. "You're pacing 23%
  over your usual Groceries spend this month."). Never invent numbers not
  present in the data.

  Respond with JSON in this exact shape: {"insights": ["...", "..."]}
  """

  @impl true
  def generate_insights(data) when is_map(data) do
    with {:ok, decoded} <- request(@insights_system_prompt, Jason.encode!(data)) do
      case decoded do
        %{"insights" => insights} when is_list(insights) ->
          {:ok, Enum.filter(insights, &is_binary/1)}

        other ->
          {:error, {:unexpected_shape, other}}
      end
    end
  end

  @recipe_system_prompt """
  You are a recipe parser. Extract the recipe's name, its ingredients, and
  a `notes` field from the provided recipe text (plain text, or text
  scraped from a recipe web page — which may include page chrome/ads/
  comments alongside the actual recipe; ignore anything that isn't part
  of the recipe itself). Do not invent ingredients — only extract what is
  explicitly present.

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

  Respond with JSON in this exact shape: {"name": "...", "notes": "...",
  "ingredients": [{"name": "...", "quantity": "...", "unit": "..."}]}
  """

  @impl true
  def parse_recipe(text) when is_binary(text) do
    with {:ok, decoded} <-
           request(@recipe_system_prompt, "Extract the recipe from the following text:\n\n" <> text) do
      case decoded do
        %{"name" => _, "notes" => _, "ingredients" => ingredients} = parsed
        when is_list(ingredients) ->
          {:ok, parsed}

        other ->
          {:error, {:unexpected_shape, other}}
      end
    end
  end

  @daily_summary_system_prompt """
  You are a household's morning assistant. Given the household's plans
  for today as JSON (a planned meal, categories at or near their monthly
  budget, unchecked grocery items, and today's calendar events — any of
  which may be absent), write a short, warm, plain-language morning
  summary: 2 to 4 sentences, reading as one short paragraph, not a bulleted
  list. Mention only what's actually present in the data — if a section is
  empty or absent, don't mention it or apologize for its absence. Never
  invent facts not present in the data. If literally nothing is present,
  respond with a brief, pleasant "nothing notable today" sentence instead
  of an empty string.

  Respond with JSON in this exact shape: {"summary": "..."}
  """

  @impl true
  def generate_daily_summary(data) when is_map(data) do
    with {:ok, decoded} <- request(@daily_summary_system_prompt, Jason.encode!(data)) do
      case decoded do
        %{"summary" => summary} when is_binary(summary) ->
          {:ok, summary}

        other ->
          {:error, {:unexpected_shape, other}}
      end
    end
  end

  defp request(system_prompt, user_content) do
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: user_content}
      ],
      response_format: %{type: "json_object"}
    }

    case Req.post(@api_url, json: body, headers: headers(), receive_timeout: 60_000) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        decode(response_body)

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp headers do
    [
      # `<> api_key()` would raise on a nil key (unlike Anthropic's client,
      # which passes the header value directly rather than concatenating
      # it) — falling back to "" keeps an unset key a normal 401 from
      # DeepSeek's server, not a local crash, matching how every other AI
      # feature in this app degrades when its key is unset.
      {"authorization", "Bearer " <> (api_key() || "")},
      {"content-type", "application/json"}
    ]
  end

  defp api_key, do: Application.fetch_env!(:budgeteer, :deepseek_api_key)

  # DeepSeek's JSON mode (unlike Anthropic's schema-constrained structured
  # outputs) only guarantees *valid* JSON, not any particular shape — each
  # caller above still checks the decoded result matches what it asked for.
  defp decode(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    case Jason.decode(content) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp decode(body), do: {:error, {:unexpected_response, body}}
end
