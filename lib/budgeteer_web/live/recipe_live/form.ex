defmodule BudgeteerWeb.RecipeLive.Form do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Meals
  alias Budgeteer.Meals.Recipe

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {@page_title}
        <:subtitle>{gettext("Use this form to manage recipes.")}</:subtitle>
      </.header>

      <.form for={@form} id="recipe-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />

        <fieldset class="fieldset mt-4">
          <legend class="fieldset-legend">{gettext("Ingredients")}</legend>

          <.inputs_for :let={ingredient_form} field={@form[:ingredients]}>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_auto] gap-2 items-end mb-2">
              <.input
                field={ingredient_form[:name]}
                type="text"
                label={gettext("Name")}
                placeholder={gettext("e.g. Onion")}
              />
              <.input field={ingredient_form[:quantity]} type="text" label={gettext("Qty")} />
              <.input
                field={ingredient_form[:unit]}
                type="text"
                label={gettext("Unit")}
                placeholder={gettext("kg, l, units")}
              />
              <.button
                type="button"
                phx-click="remove_ingredient"
                phx-value-index={ingredient_form.index}
                class="mb-2"
              >
                {gettext("Remove")}
              </.button>
            </div>
          </.inputs_for>

          <.button type="button" phx-click="add_ingredient">
            <.icon name="hero-plus" /> {gettext("Add ingredient")}
          </.button>
        </fieldset>

        <footer class="mt-4">
          <.button phx-disable-with={gettext("Saving...")} variant="primary">
            {gettext("Save recipe")}
          </.button>
          <.button navigate={return_path(@return_to, @recipe)}>{gettext("Cancel")}</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    recipe = Meals.get_recipe!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, gettext("Edit recipe"))
    |> assign(:recipe, recipe)
    |> assign(:form, to_form(Meals.change_recipe(socket.assigns.current_scope, recipe)))
  end

  defp apply_action(socket, :new, _params) do
    recipe = %Recipe{
      household_id: socket.assigns.current_scope.user.household_id,
      ingredients: []
    }

    socket
    |> assign(:page_title, gettext("New recipe"))
    |> assign(:recipe, recipe)
    |> assign(:form, to_form(Meals.change_recipe(socket.assigns.current_scope, recipe)))
  end

  @impl true
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
    save_recipe(socket, socket.assigns.live_action, recipe_params)
  end

  defp update_ingredients(socket, fun) do
    changeset = socket.assigns.form.source
    ingredients = Ecto.Changeset.get_field(changeset, :ingredients, [])
    Ecto.Changeset.put_embed(changeset, :ingredients, fun.(ingredients))
  end

  defp save_recipe(socket, :edit, recipe_params) do
    case Meals.update_recipe(socket.assigns.current_scope, socket.assigns.recipe, recipe_params) do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Recipe updated successfully"))
         |> push_navigate(to: return_path(socket.assigns.return_to, recipe))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_recipe(socket, :new, recipe_params) do
    case Meals.create_recipe(socket.assigns.current_scope, recipe_params) do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Recipe created successfully"))
         |> push_navigate(to: return_path(socket.assigns.return_to, recipe))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _recipe), do: ~p"/recipes"
  defp return_path("show", recipe), do: ~p"/recipes/#{recipe}"
end
