defmodule Budgeteer.RecipeUrlFetcherTest do
  use ExUnit.Case, async: true

  alias Budgeteer.RecipeUrlFetcher

  describe "fetch/1 validation (no network involved — rejected before any request is made)" do
    test "rejects a malformed URL" do
      assert {:error, :invalid_url} = RecipeUrlFetcher.fetch("not a url")
    end

    test "rejects a non-http(s) scheme" do
      assert {:error, :invalid_url} = RecipeUrlFetcher.fetch("ftp://example.com/recipe")
    end

    test "rejects a loopback host" do
      assert {:error, :unsafe_host} = RecipeUrlFetcher.fetch("http://127.0.0.1/recipe")
      assert {:error, :unsafe_host} = RecipeUrlFetcher.fetch("http://localhost/recipe")
    end

    test "rejects a private-range host" do
      assert {:error, :unsafe_host} = RecipeUrlFetcher.fetch("http://192.168.1.1/recipe")
      assert {:error, :unsafe_host} = RecipeUrlFetcher.fetch("http://10.0.0.5/recipe")
    end

    test "rejects the cloud-metadata link-local address" do
      assert {:error, :unsafe_host} = RecipeUrlFetcher.fetch("http://169.254.169.254/recipe")
    end
  end

  describe "extract_text/1 — schema.org Recipe JSON-LD" do
    test "prefers structured JSON-LD data over the surrounding page text" do
      html = """
      <html>
        <body>
          <nav>Site nav junk</nav>
          <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "Recipe",
            "name": "Tomato Soup",
            "description": "A simple soup.",
            "recipeYield": "4 servings",
            "recipeIngredient": ["6 tomatoes", "1 onion", "Salt to taste"],
            "recipeInstructions": [
              {"@type": "HowToStep", "text": "Chop the vegetables."},
              {"@type": "HowToStep", "text": "Simmer for 20 minutes."}
            ]
          }
          </script>
          <footer>Copyright junk</footer>
        </body>
      </html>
      """

      text = RecipeUrlFetcher.extract_text(html)

      assert text =~ "Tomato Soup"
      assert text =~ "6 tomatoes"
      assert text =~ "Chop the vegetables."
      assert text =~ "Simmer for 20 minutes."
      refute text =~ "Site nav junk"
      refute text =~ "Copyright junk"
    end

    test "finds a Recipe node nested under @graph" do
      html = """
      <script type="application/ld+json">
      {
        "@graph": [
          {"@type": "WebPage", "name": "irrelevant"},
          {"@type": ["Recipe", "Thing"], "name": "Pancakes", "recipeIngredient": ["Flour"]}
        ]
      }
      </script>
      """

      assert RecipeUrlFetcher.extract_text(html) =~ "Pancakes"
    end

    test "falls back to visible text when no Recipe JSON-LD is present" do
      html = """
      <html>
        <body>
          <script>console.log("noise")</script>
          <style>.x { color: red; }</style>
          <main>Grandma's Pancakes. 2 cups flour. Mix and fry.</main>
        </body>
      </html>
      """

      text = RecipeUrlFetcher.extract_text(html)

      assert text =~ "Grandma's Pancakes"
      assert text =~ "2 cups flour"
      refute text =~ "console.log"
      refute text =~ "color: red"
    end

    test "returns an empty string for unparseable input" do
      assert RecipeUrlFetcher.extract_text("") == ""
    end
  end
end
