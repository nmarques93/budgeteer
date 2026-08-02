defmodule Budgeteer.RecipeUrlFetcher do
  @moduledoc """
  Fetches a web page believed to contain a recipe and reduces it to plain
  text suitable for `Budgeteer.AI.DeepSeekClient.parse_recipe/1` — this
  reuses the exact same extraction/review flow as pasting text, rather
  than teaching the AI client (or its schema) anything about HTML.

  Prefers a page's own schema.org `Recipe` JSON-LD block if present — most
  recipe sites embed one for SEO, and it's already clean, structured data
  (ingredients + instructions with none of the surrounding page chrome/
  ads/comments that visible-text scraping would otherwise pick up). Falls
  back to stripped visible text otherwise.

  Basic SSRF guardrail: the resolved host must not be a loopback/private/
  link-local address (blocks the obvious `http://localhost`,
  `http://169.254.169.254` cloud-metadata cases). This is a best-effort
  check at fetch time, not a redirect-aware or DNS-rebinding-proof one —
  proportionate to a single-household app's actual threat model, not a
  public multi-tenant service.
  """

  @behaviour Budgeteer.RecipeUrlFetcherBehaviour

  @user_agent "Mozilla/5.0 (compatible; BudgeteerBot/1.0; +recipe-import)"
  @max_text_chars 20_000

  @impl true
  def fetch(url) when is_binary(url) do
    with {:ok, url} <- validate_url(url),
         {:ok, html} <- get_html(url) do
      case extract_text(html) do
        "" -> {:error, :no_content_found}
        text -> {:ok, String.slice(text, 0, @max_text_chars)}
      end
    end
  end

  @doc """
  Reduces an HTML document to plain text — the pure part of `fetch/1`,
  pulled out so it's directly testable with hand-written HTML fixtures
  instead of needing a real (or stubbed) network call.
  """
  def extract_text(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        case extract_recipe_json_ld(document) do
          nil -> extract_visible_text(document)
          text -> text
        end

      {:error, _reason} ->
        ""
    end
  end

  defp validate_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if safe_host?(host), do: {:ok, url}, else: {:error, :unsafe_host}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp safe_host?(host) do
    charlist = String.to_charlist(host)

    case :inet.getaddr(charlist, :inet) do
      {:ok, ip} -> not private_ip?(ip)
      {:error, _} -> safe_host_v6?(charlist)
    end
  end

  defp safe_host_v6?(charlist) do
    case :inet.getaddr(charlist, :inet6) do
      {:ok, ip} -> not private_ip?(ip)
      {:error, _} -> false
    end
  end

  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({172, b, _, _}) when b in 16..31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({169, 254, _, _}), do: true
  defp private_ip?({0, 0, 0, 0}), do: true
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_ip?({first, _, _, _, _, _, _, _}) when first in 0xFC00..0xFDFF, do: true
  defp private_ip?({first, _, _, _, _, _, _, _}) when first in 0xFE80..0xFEBF, do: true
  defp private_ip?(_), do: false

  defp get_html(url) do
    case Req.get(url,
           headers: [{"user-agent", @user_agent}],
           receive_timeout: 20_000,
           max_redirects: 3,
           decode_body: false
         ) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, to_string(body)}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_error, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp extract_recipe_json_ld(document) do
    document
    |> Floki.find("script[type='application/ld+json']")
    |> Enum.find_value(fn node ->
      with text <- raw_text(node),
           {:ok, decoded} <- Jason.decode(text),
           %{} = recipe <- find_recipe(decoded) do
        recipe_to_text(recipe)
      else
        _ -> nil
      end
    end)
  end

  # Floki.text/1 deliberately skips <script> content (it's not "visible
  # text"), so a JSON-LD block's literal contents have to be read straight
  # off the node's children instead.
  defp raw_text({_tag, _attrs, children}), do: Enum.join(children, "")
  defp raw_text(_node), do: ""

  defp find_recipe(%{"@graph" => graph}) when is_list(graph), do: find_recipe(graph)
  defp find_recipe(list) when is_list(list), do: Enum.find_value(list, &find_recipe/1)
  defp find_recipe(%{"@type" => type} = node), do: if(recipe_type?(type), do: node)
  defp find_recipe(_), do: nil

  defp recipe_type?(type) when is_binary(type), do: type == "Recipe"
  defp recipe_type?(types) when is_list(types), do: "Recipe" in types
  defp recipe_type?(_), do: false

  defp recipe_to_text(recipe) do
    name = Map.get(recipe, "name", "")
    description = Map.get(recipe, "description", "")
    yield = Map.get(recipe, "recipeYield")
    ingredients = recipe |> Map.get("recipeIngredient", []) |> List.wrap()
    instructions = instructions_to_lines(Map.get(recipe, "recipeInstructions"))

    [
      "Recipe: #{name}",
      if(description != "", do: description),
      if(yield, do: "Servings: #{stringify(yield)}"),
      "",
      "Ingredients:",
      Enum.map_join(ingredients, "\n", &("- " <> stringify(&1))),
      "",
      "Instructions:",
      Enum.map_join(instructions, "\n", &("- " <> &1))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp instructions_to_lines(nil), do: []
  defp instructions_to_lines(text) when is_binary(text), do: [text]

  defp instructions_to_lines(list) when is_list(list) do
    list
    |> Enum.map(fn
      %{"text" => text} -> text
      %{"itemListElement" => nested} -> nested |> instructions_to_lines() |> Enum.join(" ")
      text when is_binary(text) -> text
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp instructions_to_lines(_), do: []

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp extract_visible_text(document) do
    document
    |> Floki.filter_out("script")
    |> Floki.filter_out("style")
    |> Floki.filter_out("nav")
    |> Floki.filter_out("header")
    |> Floki.filter_out("footer")
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
