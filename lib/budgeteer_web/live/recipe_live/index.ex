defmodule BudgeteerWeb.RecipeLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Meals

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Recipes
        <:actions>
          <.button variant="primary" navigate={~p"/recipes/new"}>
            <.icon name="hero-plus" /> New recipe
          </.button>
        </:actions>
      </.header>

      <.table
        id="recipes"
        rows={@streams.recipes}
        row_click={fn {_id, recipe} -> JS.navigate(~p"/recipes/#{recipe}") end}
      >
        <:col :let={{_id, recipe}} label="Name">{recipe.name}</:col>
        <:col :let={{_id, recipe}} label="Ingredients">{length(recipe.ingredients)}</:col>
        <:action :let={{id, recipe}}>
          <.link
            phx-click={JS.push("delete", value: %{id: recipe.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Meals.subscribe_recipes(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Recipes")
     |> stream(:recipes, Meals.list_recipes(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    recipe = Meals.get_recipe!(socket.assigns.current_scope, id)
    {:ok, _} = Meals.delete_recipe(socket.assigns.current_scope, recipe)

    {:noreply, stream_delete(socket, :recipes, recipe)}
  end

  @impl true
  def handle_info({type, %Budgeteer.Meals.Recipe{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, stream(socket, :recipes, Meals.list_recipes(socket.assigns.current_scope), reset: true)}
  end
end
