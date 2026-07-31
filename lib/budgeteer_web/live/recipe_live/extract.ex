defmodule BudgeteerWeb.RecipeLive.Extract do
  @moduledoc """
  Paste a recipe's text and have `Budgeteer.AI` extract structured
  ingredients — mirrors the bank-statement-import pattern (extract, then
  review and confirm before anything saves), but synchronously via
  `start_async/3` rather than an Oban job: a recipe extraction is small
  and fast enough not to need the statement pipeline's async-job/status
  machinery, and this way the whole extract-then-review flow stays one
  LiveView process with no redirect round-trip.

  File/photo upload (the other half of the original ask) is deliberately
  not built yet — `StatementController`'s plain-multipart-POST pattern
  would be the proven-safe way to do it (LiveView's own `allow_upload`
  mysteriously failed for statement upload in this exact codebase; see
  CLAUDE.md), but handing the uploaded file's extraction result back into
  this LiveView's review phase would need a session-stash-and-redirect
  detour with no clean precedent here yet. Flagged, not silently dropped.
  """
  use BudgeteerWeb, :live_view

  alias Budgeteer.Meals
  alias Budgeteer.Meals.Recipe

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Extract Recipe
        <:subtitle>
          Paste a recipe's text and Budgeteer will pull out the ingredients — review and edit before saving.
        </:subtitle>
      </.header>

      <.form :if={@phase == :input} for={@text_form} id="extract-text-form" phx-submit="extract_text">
        <.input
          field={@text_form[:text]}
          type="textarea"
          label="Recipe text"
          rows="12"
          placeholder="Paste a recipe here, ingredients and all..."
        />
        <footer class="mt-4">
          <.button phx-disable-with="Extracting..." variant="primary">Extract Recipe</.button>
          <.button navigate={~p"/recipes"}>Cancel</.button>
        </footer>
      </.form>

      <div :if={@phase == :extracting} class="mt-4 flex items-center gap-2 text-base-content/60">
        <span class="loading loading-spinner loading-sm"></span> Extracting the recipe...
      </div>

      <div :if={@phase == :reviewing}>
        <p class="text-sm text-base-content/60 mb-4">
          Review the extracted recipe below — nothing is saved until you confirm.
        </p>

        <.form for={@form} id="recipe-review-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:notes]} type="textarea" label="Notes" />

          <fieldset class="fieldset mt-4">
            <legend class="fieldset-legend">Ingredients</legend>

            <.inputs_for :let={ingredient_form} field={@form[:ingredients]}>
              <div class="flex gap-2 items-end mb-2">
                <.input
                  field={ingredient_form[:name]}
                  type="text"
                  label="Name"
                  placeholder="e.g. Onion"
                />
                <.input field={ingredient_form[:quantity]} type="text" label="Qty" />
                <.input
                  field={ingredient_form[:unit]}
                  type="text"
                  label="Unit"
                  placeholder="kg, l, units"
                />
                <.button
                  type="button"
                  phx-click="remove_ingredient"
                  phx-value-index={ingredient_form.index}
                  class="mb-2"
                >
                  Remove
                </.button>
              </div>
            </.inputs_for>

            <.button type="button" phx-click="add_ingredient">
              <.icon name="hero-plus" /> Add ingredient
            </.button>
          </fieldset>

          <footer class="mt-4">
            <.button phx-disable-with="Saving..." variant="primary">Save Recipe</.button>
            <.button navigate={~p"/recipes"}>Cancel</.button>
          </footer>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Extract Recipe")
     |> assign(:phase, :input)
     |> assign(:text_form, to_form(%{"text" => ""}, as: "recipe_text"))}
  end

  @impl true
  def handle_event("extract_text", %{"recipe_text" => %{"text" => text}}, socket) do
    if String.trim(text) == "" do
      {:noreply, put_flash(socket, :error, "Paste some recipe text first")}
    else
      {:noreply,
       socket
       |> assign(:phase, :extracting)
       |> start_async(:extract, fn -> ai_client().parse_recipe({:text, text}) end)}
    end
  end

  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    changeset =
      Meals.change_recipe(socket.assigns.current_scope, socket.assigns.recipe, recipe_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("add_ingredient", _params, socket) do
    {:noreply,
     assign(socket,
       form: to_form(update_ingredients(socket, &(&1 ++ [%Budgeteer.Meals.Ingredient{}])))
     )}
  end

  def handle_event("remove_ingredient", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    {:noreply,
     assign(socket, form: to_form(update_ingredients(socket, &List.delete_at(&1, index))))}
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    case Meals.create_recipe(socket.assigns.current_scope, recipe_params) do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe created successfully")
         |> push_navigate(to: ~p"/recipes/#{recipe}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_async(:extract, {:ok, {:ok, parsed}}, socket) do
    scope = socket.assigns.current_scope
    recipe = %Recipe{household_id: scope.user.household_id, ingredients: []}
    changeset = Meals.change_recipe(scope, recipe, extracted_attrs(parsed))

    {:noreply,
     socket
     |> assign(:phase, :reviewing)
     |> assign(:recipe, recipe)
     |> assign(:form, to_form(changeset))}
  end

  def handle_async(:extract, {:ok, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :input)
     |> put_flash(
       :error,
       "Couldn't extract a recipe from that text — try rephrasing, or add it manually."
     )}
  end

  def handle_async(:extract, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :input)
     |> put_flash(:error, "Something went wrong extracting the recipe — please try again.")}
  end

  defp ai_client, do: Application.get_env(:budgeteer, :ai_client, Budgeteer.AI.Client)

  defp extracted_attrs(parsed) do
    %{
      "name" => parsed["name"] || "",
      "notes" => blank_to_nil(parsed["notes"]),
      "ingredients" =>
        parsed
        |> Map.get("ingredients", [])
        |> Enum.map(fn ingredient ->
          %{
            "name" => ingredient["name"] || "",
            "quantity" => blank_to_nil(ingredient["quantity"]),
            "unit" => blank_to_nil(ingredient["unit"])
          }
        end)
    }
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp update_ingredients(socket, fun) do
    changeset = socket.assigns.form.source
    ingredients = Ecto.Changeset.get_field(changeset, :ingredients, [])
    Ecto.Changeset.put_embed(changeset, :ingredients, fun.(ingredients))
  end
end
