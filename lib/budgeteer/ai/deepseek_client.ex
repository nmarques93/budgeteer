defmodule Budgeteer.AI.DeepSeekClient do
  @moduledoc """
  Calls DeepSeek's chat completions API (OpenAI-compatible) to turn a
  household's spending data into a handful of natural-language budget
  insights. Deliberately a separate, cheaper model from
  `Budgeteer.AI.Client` (Anthropic) — spotting "this is worth mentioning"
  in a small pre-computed JSON summary is a good-enough-model task, not a
  document-extraction one, so it doesn't need Claude's accuracy or cost.
  Elixir has no official DeepSeek SDK, so this is raw HTTP via `Req`, same
  as the Anthropic client.
  """

  @behaviour Budgeteer.AI.DeepSeekClientBehaviour

  @api_url "https://api.deepseek.com/chat/completions"
  @model "deepseek-chat"

  @system_prompt """
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
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: @system_prompt},
        %{role: "user", content: Jason.encode!(data)}
      ],
      response_format: %{type: "json_object"}
    }

    case Req.post(@api_url, json: body, headers: headers(), receive_timeout: 60_000) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        handle_success(response_body)

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

  defp handle_success(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    case Jason.decode(content) do
      {:ok, %{"insights" => insights}} when is_list(insights) ->
        {:ok, Enum.filter(insights, &is_binary/1)}

      {:ok, other} ->
        {:error, {:unexpected_shape, other}}

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  defp handle_success(body), do: {:error, {:unexpected_response, body}}
end
