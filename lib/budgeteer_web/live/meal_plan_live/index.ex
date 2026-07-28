defmodule BudgeteerWeb.MealPlanLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Meals
  alias Budgeteer.Meals.PlannedMeal
  alias Budgeteer.Groceries

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Meal plan
        <:subtitle>Upcoming meals, soonest first</:subtitle>
      </.header>

      <.form for={@plan_form} id="plan-meal-form" phx-submit="plan_meal" class="flex gap-2 items-end mt-4">
        <.input field={@plan_form[:date]} type="date" label="Date" />
        <.input
          field={@plan_form[:recipe_id]}
          type="select"
          label="Recipe"
          options={Enum.map(@recipes, &{&1.name, &1.id})}
          prompt="Choose a recipe"
        />
        <.button phx-disable-with="Adding..." variant="primary">Plan meal</.button>
      </.form>
      <p :if={@recipes == []} class="text-sm opacity-70 mt-1">
        You don't have any recipes yet — <.link navigate={~p"/recipes/new"} class="link">create one</.link> first.
      </p>

      <ul id="planned-meals" phx-update="stream" class="mt-6 space-y-1">
        <li :for={{id, planned_meal} <- @streams.planned_meals} id={id} class="flex items-center gap-3">
          <span class="font-mono tabular-nums opacity-70">{planned_meal.date}</span>
          <.link navigate={~p"/recipes/#{planned_meal.recipe}"} class="link">{planned_meal.recipe.name}</.link>
          <.link phx-click={JS.push("delete", value: %{id: planned_meal.id})} data-confirm="Are you sure?">
            <.icon name="hero-trash" class="size-4" />
          </.link>
        </li>
      </ul>

      <div :if={@planned_meals != []} class="mt-6">
        <.form for={@add_form} id="add-to-list-form" phx-submit="add_to_grocery_list" class="flex gap-2 items-end">
          <.input
            field={@add_form[:grocery_list_id]}
            type="select"
            label="Add every listed ingredient to"
            options={Enum.map(@grocery_lists, &{&1.name, &1.id})}
            prompt="Choose a list"
          />
          <.button phx-disable-with="Adding..." variant="primary">Add ingredients</.button>
        </.form>
        <p :if={@grocery_lists == []} class="text-sm opacity-70 mt-1">
          You don't have a grocery list yet — <.link navigate={~p"/groceries/new"} class="link">create one</.link> first.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Meals.subscribe_planned_meals(scope)
    end

    planned_meals = Meals.list_planned_meals(scope)

    {:ok,
     socket
     |> assign(:page_title, "Meal plan")
     |> assign(:recipes, Meals.list_recipes(scope))
     |> assign(:grocery_lists, Groceries.list_grocery_lists(scope))
     |> assign(:planned_meals, planned_meals)
     |> assign(:plan_form, to_form(%{"date" => nil, "recipe_id" => nil}, as: "plan"))
     |> assign(:add_form, to_form(%{"grocery_list_id" => nil}, as: "add_to_list"))
     |> stream(:planned_meals, planned_meals)}
  end

  @impl true
  def handle_event("plan_meal", %{"plan" => plan_params}, socket) do
    case Meals.create_planned_meal(socket.assigns.current_scope, plan_params) do
      {:ok, planned_meal} ->
        {:noreply,
         socket
         |> stream_insert(:planned_meals, planned_meal)
         |> assign(:planned_meals, [planned_meal | socket.assigns.planned_meals])
         |> assign(:plan_form, to_form(%{"date" => nil, "recipe_id" => nil}, as: "plan"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :plan_form, to_form(changeset, as: "plan"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    planned_meal = Enum.find(socket.assigns.planned_meals, &(&1.id == id))
    {:ok, _} = Meals.delete_planned_meal(scope, planned_meal)

    {:noreply,
     socket
     |> stream_delete(:planned_meals, planned_meal)
     |> assign(:planned_meals, Enum.reject(socket.assigns.planned_meals, &(&1.id == id)))}
  end

  def handle_event("add_to_grocery_list", %{"add_to_list" => %{"grocery_list_id" => grocery_list_id}}, socket) do
    scope = socket.assigns.current_scope
    grocery_list = Groceries.get_grocery_list!(scope, grocery_list_id)
    recipes = Enum.map(socket.assigns.planned_meals, & &1.recipe)

    {:ok, count} = Meals.add_ingredients_to_grocery_list(scope, recipes, grocery_list)

    {:noreply, put_flash(socket, :info, "Added #{count} ingredient(s) to \"#{grocery_list.name}\"")}
  end

  @impl true
  def handle_info({:created, %PlannedMeal{} = planned_meal}, socket) do
    {:noreply,
     socket
     |> stream_insert(:planned_meals, planned_meal)
     |> put_planned_meal(planned_meal)}
  end

  def handle_info({:deleted, %PlannedMeal{} = planned_meal}, socket) do
    {:noreply,
     socket
     |> stream_delete(:planned_meals, planned_meal)
     |> assign(:planned_meals, Enum.reject(socket.assigns.planned_meals, &(&1.id == planned_meal.id)))}
  end

  defp put_planned_meal(socket, planned_meal) do
    if Enum.any?(socket.assigns.planned_meals, &(&1.id == planned_meal.id)) do
      socket
    else
      assign(socket, :planned_meals, [planned_meal | socket.assigns.planned_meals])
    end
  end
end
