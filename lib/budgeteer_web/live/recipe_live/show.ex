defmodule BudgeteerWeb.RecipeLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Meals
  alias Budgeteer.Groceries

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {@recipe.name}
        <:actions>
          <.button navigate={~p"/recipes"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button navigate={~p"/recipes/#{@recipe}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> {gettext("Edit recipe")}
          </.button>
        </:actions>
      </.header>

      <div :if={@recipe.image_path} class="mb-4">
        <img
          src={~p"/recipes/#{@recipe}/image"}
          alt={@recipe.name}
          class="rounded-box max-w-sm w-full object-cover"
        />
      </div>

      <div class="mb-4">
        <.form
          for={%{}}
          id="recipe-image-form"
          action={~p"/recipes/#{@recipe}/image"}
          method="post"
          multipart
          class="flex gap-2 items-end flex-wrap"
        >
          <div>
            <label class="label" for="recipe-image-input">
              {if @recipe.image_path, do: gettext("Replace image"), else: gettext("Add an image")}
            </label>
            <input
              id="recipe-image-input"
              type="file"
              name="image"
              accept=".jpg,.jpeg,.png"
              required
              class="w-full"
            />
          </div>
          <.button phx-disable-with={gettext("Uploading...")}>
            <.icon name="hero-photo" /> {gettext("Upload")}
          </.button>
        </.form>
        <.link
          :if={@recipe.image_path}
          phx-click="remove_image"
          data-confirm={gettext("Remove this image?")}
          class="link text-sm mt-1 inline-block"
        >
          {gettext("Remove image")}
        </.link>
      </div>

      <p :if={@recipe.notes} class="opacity-70 mb-4">{@recipe.notes}</p>

      <ul class="list">
        <li :for={ingredient <- @recipe.ingredients} class="list-row">
          {ingredient.name}
          <span :if={ingredient.quantity} class="opacity-70 text-sm">
            ({ingredient.quantity} {ingredient.unit})
          </span>
        </li>
      </ul>

      <div :if={@recipe.ingredients != []} class="mt-6">
        <.form
          for={@add_form}
          id="add-to-list-form"
          phx-submit="add_to_grocery_list"
          class="grid grid-cols-1 sm:grid-cols-[minmax(0,1fr)_auto] gap-2 items-end"
        >
          <.input
            field={@add_form[:grocery_list_id]}
            type="select"
            label={gettext("Add ingredients to")}
            options={Enum.map(@grocery_lists, &{&1.name, &1.id})}
            prompt={gettext("Choose a list")}
          />
          <.button phx-disable-with={gettext("Adding...")} variant="primary">
            {gettext("Add ingredients")}
          </.button>
        </.form>
        <p :if={@grocery_lists == []} class="text-sm opacity-70 mt-1">
          {gettext("You don't have a grocery list yet —")}
          <.link navigate={~p"/groceries/new"} class="link">{gettext("create one")}</.link>
          {gettext("first.")}
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    recipe = Meals.get_recipe!(socket.assigns.current_scope, id)
    grocery_lists = Groceries.list_grocery_lists(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, recipe.name)
     |> assign(:recipe, recipe)
     |> assign(:grocery_lists, grocery_lists)
     |> assign(:add_form, to_form(%{"grocery_list_id" => nil}, as: "add_to_list"))}
  end

  @impl true
  def handle_event("remove_image", _params, socket) do
    {:ok, recipe} = Meals.remove_recipe_image(socket.assigns.current_scope, socket.assigns.recipe)

    {:noreply, assign(socket, :recipe, recipe)}
  end

  def handle_event(
        "add_to_grocery_list",
        %{"add_to_list" => %{"grocery_list_id" => grocery_list_id}},
        socket
      ) do
    scope = socket.assigns.current_scope
    grocery_list = Groceries.get_grocery_list!(scope, grocery_list_id)

    {:ok, count} =
      Meals.add_ingredients_to_grocery_list(scope, [socket.assigns.recipe], grocery_list)

    {:noreply,
     put_flash(
       socket,
       :info,
       ngettext(
         "Added 1 ingredient to \"%{list}\"",
         "Added %{count} ingredients to \"%{list}\"",
         count,
         list: grocery_list.name
       )
     )}
  end
end
