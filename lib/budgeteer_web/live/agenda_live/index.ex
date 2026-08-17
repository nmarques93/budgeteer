defmodule BudgeteerWeb.AgendaLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.{Events, Groceries, Ledger, Meals, Todos}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      online_members={@online_members}
      container_class="max-w-4xl"
    >
      <.header>
        {gettext("Household agenda")}
        <:subtitle>{gettext("Everything your household has planned this week.")}</:subtitle>
        <:actions>
          <.button navigate={~p"/calendar/new?#{[date: Date.to_iso8601(@today)]}"}>
            <.icon name="hero-plus" /> {gettext("New event")}
          </.button>
        </:actions>
      </.header>

      <div class="flex items-center justify-between mt-4">
        <.link
          patch={~p"/agenda?#{[week: Date.to_iso8601(Date.add(@week_start, -7))]}"}
          class="btn btn-sm btn-ghost"
          aria-label={gettext("Previous week")}
        >
          <.icon name="hero-chevron-left" />
        </.link>
        <div class="text-center">
          <h2 class="font-semibold">{week_label(@week_start, @week_end)}</h2>
          <.link patch={~p"/agenda"} class="btn btn-xs btn-outline mt-1">{gettext("This week")}</.link>
        </div>
        <.link
          patch={~p"/agenda?#{[week: Date.to_iso8601(Date.add(@week_start, 7))]}"}
          class="btn btn-sm btn-ghost"
          aria-label={gettext("Next week")}
        >
          <.icon name="hero-chevron-right" />
        </.link>
      </div>

      <div id="agenda-days" class="grid gap-3 mt-6 md:grid-cols-2">
        <section
          :for={day <- @days}
          class={[
            "rounded border p-4",
            day.date == @today && "border-primary bg-primary/5",
            "border-base-300"
          ]}
        >
          <h3 class="font-semibold">{day_label(day.date)}</h3>
          <div :if={day.items == []} class="text-sm opacity-60 mt-3">
            {gettext("Nothing planned.")}
          </div>
          <div :for={item <- day.items} class="mt-3">
            <%= case item.kind do %>
              <% :event -> %>
                <%= if item.value.source == :google do %>
                  <a
                    href={item.value.external_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block rounded bg-base-200 p-3"
                  >
                    <span class="text-xs uppercase opacity-60">{gettext("Calendar")}</span>
                    <span class="block font-medium">{item.value.title}</span>
                  </a>
                <% else %>
                  <.link
                    navigate={~p"/calendar/#{item.value}/edit"}
                    class="block rounded bg-base-200 p-3"
                  >
                    <span class="text-xs uppercase opacity-60">{gettext("Calendar")}</span>
                    <span class="block font-medium">{item.value.title}</span>
                  </.link>
                <% end %>
              <% :todo -> %>
                <.link
                  navigate={~p"/todos/#{item.value.todo_list_id}"}
                  class="block rounded bg-primary text-primary-content p-3"
                >
                  <span class="text-xs uppercase opacity-80">{gettext("TODO")}</span>
                  <span class="block font-medium">{item.value.title}</span>
                </.link>
              <% :meal -> %>
                <.link navigate={~p"/meal-plan"} class="block rounded bg-secondary/20 p-3">
                  <span class="text-xs uppercase opacity-60">{gettext("Meal")}</span>
                  <span class="block font-medium">{item.value.recipe.name}</span>
                </.link>
            <% end %>
          </div>
        </section>
      </div>

      <div class="grid gap-4 mt-6 md:grid-cols-2">
        <section class="rounded border border-base-300 p-4">
          <h2 class="font-semibold">{gettext("Shopping list")}</h2>
          <p :if={@shopping_items == []} class="text-sm opacity-60 mt-2">
            {gettext("Nothing unchecked.")}
          </p>
          <ul :if={@shopping_items != []} class="mt-2 space-y-1 text-sm">
            <li :for={item <- @shopping_items} class="flex justify-between gap-3">
              <span>{item.name}</span><span class="opacity-60">{item.list_name}</span>
            </li>
          </ul>
        </section>
        <section class="rounded border border-base-300 p-4">
          <h2 class="font-semibold">{gettext("Budget alerts")}</h2>
          <p :if={@budget_alerts == []} class="text-sm opacity-60 mt-2">
            {gettext("No categories have reached budget this month.")}
          </p>
          <ul :if={@budget_alerts != []} class="mt-2 space-y-1 text-sm">
            <li :for={category <- @budget_alerts} class="flex items-center gap-2 text-error">
              <.icon name={category.icon} class="size-4" /> {category.name}
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Events.subscribe_events(scope)
      Todos.subscribe_todo_items(scope)
      Meals.subscribe_planned_meals(scope)
      Ledger.subscribe_transactions(scope)
      Ledger.subscribe_categories(scope)

      for list <- Groceries.list_grocery_lists(scope), do: Groceries.subscribe_items(scope, list)
    end

    {:ok, assign(socket, :page_title, gettext("Household agenda"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    week_start = parse_week(params["week"])
    {:noreply, load_agenda(socket, week_start)}
  end

  @impl true
  def handle_info({_type, _record}, socket) do
    {:noreply, load_agenda(socket, socket.assigns.week_start)}
  end

  defp load_agenda(socket, week_start) do
    week_end = Date.add(week_start, 6)
    scope = socket.assigns.current_scope

    events = Events.list_events(scope, week_start, week_end)
    todos = Todos.list_due_items(scope, week_start, week_end)
    meals = Meals.list_planned_meals_between(scope, week_start, week_end)

    days =
      Date.range(week_start, week_end)
      |> Enum.map(fn date ->
        items =
          Enum.map(Enum.filter(events, &(&1.date == date)), &%{kind: :event, value: &1}) ++
            Enum.map(Enum.filter(todos, &(&1.due_date == date)), &%{kind: :todo, value: &1}) ++
            Enum.map(Enum.filter(meals, &(&1.date == date)), &%{kind: :meal, value: &1})

        %{date: date, items: items}
      end)

    shopping_items =
      for list <- Groceries.list_grocery_lists(scope),
          item <- Groceries.list_items(scope, list),
          not item.checked do
        %{name: item.name, list_name: list.name}
      end

    socket
    |> assign(:today, Date.utc_today())
    |> assign(:week_start, week_start)
    |> assign(:week_end, week_end)
    |> assign(:days, days)
    |> assign(:shopping_items, shopping_items)
    |> assign(:budget_alerts, Ledger.list_current_budget_alerts(scope))
  end

  defp parse_week(nil), do: week_start(Date.utc_today())

  defp parse_week(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> week_start(date)
      {:error, _} -> week_start(Date.utc_today())
    end
  end

  defp week_start(date), do: Date.add(date, -(Date.day_of_week(date) - 1))
  defp week_label(start_date, end_date), do: "#{start_date} - #{end_date}"
  defp day_label(date), do: Calendar.strftime(date, "%A %-d %B")
end
