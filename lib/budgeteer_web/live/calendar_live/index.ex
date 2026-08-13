defmodule BudgeteerWeb.CalendarLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Events
  alias Budgeteer.Households
  alias Budgeteer.Todos
  alias Budgeteer.Todos.TodoItem

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
        {gettext("Calendar")}
        <:actions>
          <.button
            variant="primary"
            navigate={~p"/calendar/new?#{[date: Date.to_iso8601(Date.utc_today())]}"}
          >
            <.icon name="hero-plus" /> {gettext("New Event")}
          </.button>
        </:actions>
      </.header>

      <div class="flex items-center justify-between mt-4">
        <.link
          patch={~p"/calendar?#{[month: Date.to_iso8601(shift_month(@month, -1))]}"}
          class="btn btn-sm btn-ghost"
          aria-label={gettext("Previous month")}
        >
          <.icon name="hero-chevron-left" />
        </.link>
        <div class="flex items-center gap-3">
          <h2 class="text-lg font-semibold">{month_label(@month)}</h2>
          <.link patch={~p"/calendar"} class="btn btn-xs btn-outline">{gettext("Today")}</.link>
        </div>
        <.link
          patch={~p"/calendar?#{[month: Date.to_iso8601(shift_month(@month, 1))]}"}
          class="btn btn-sm btn-ghost"
          aria-label={gettext("Next month")}
        >
          <.icon name="hero-chevron-right" />
        </.link>
      </div>

      <div :if={@members != []} class="flex flex-wrap gap-x-4 gap-y-1 mt-4 text-xs">
        <div class="flex items-center gap-1.5">
          <span class="inline-block size-2 rounded-full bg-base-content/50"></span>
          <span class="opacity-70">{gettext("Whole household")}</span>
        </div>
        <div :for={member <- @members} class="flex items-center gap-1.5">
          <span
            class="inline-block size-2 rounded-full"
            style={"background-color: #{member_color(@member_colors, member.id)}"}
          ></span>
          <span class="opacity-70">{display_name(member)}</span>
        </div>
      </div>

      <div class="grid grid-cols-7 gap-px mt-4 bg-base-300 border border-base-300 rounded overflow-hidden text-xs">
        <div
          :for={label <- weekday_labels()}
          class="bg-base-200 px-2 py-1 text-center font-semibold opacity-70"
        >
          {label}
        </div>
        <div
          :for={date <- @grid_dates}
          class={[
            "bg-base-100 p-1 min-h-24 flex flex-col gap-0.5",
            date.month != @month.month && "opacity-40"
          ]}
        >
          <.link
            navigate={~p"/calendar/new?#{[date: Date.to_iso8601(date)]}"}
            class={["text-right block px-0.5", date == @today && "font-bold text-primary"]}
          >
            {date.day}
          </.link>
          <%= for event <- visible_events(@events_by_date, date, @expanded_dates) do %>
            <a
              :if={event.source == :google}
              href={event.external_url}
              target="_blank"
              rel="noopener noreferrer"
              class={event_classes(event)}
              style={"background-color: #{event_color(@member_colors, event)}"}
              title={event.title}
            >
              {event.title}
            </a>
            <.link
              :if={event.source != :google}
              navigate={~p"/calendar/#{event}/edit"}
              class={event_classes(event)}
              style={"background-color: #{event_color(@member_colors, event)}"}
              title={event.title}
            >
              {event.title}
            </.link>
          <% end %>
          <.link
            :for={todo <- Map.get(@todos_by_date, date, [])}
            navigate={~p"/todos/#{todo.todo_list_id}"}
            class="block truncate rounded px-1 py-0.5 text-left bg-primary text-primary-content"
            title={todo.title}
          >
            <.icon name="hero-check-circle" class="size-3 align-text-bottom" /> {todo.title}
          </.link>
          <div
            :if={length(Map.get(@events_by_date, date, [])) > 3}
            class="px-1 text-[10px] opacity-60"
          >
            <button
              type="button"
              phx-click="toggle_day"
              phx-value-date={Date.to_iso8601(date)}
              class="link"
            >
              <%= if MapSet.member?(@expanded_dates, date) do %>
                {gettext("Show less")}
              <% else %>
                {gettext("+%{count} more", count: length(Map.get(@events_by_date, date, [])) - 3)}
              <% end %>
            </button>
          </div>
        </div>
      </div>

      <div id="calendar-agenda" class="md:hidden mt-6 space-y-4">
        <section :for={date <- agenda_dates(@grid_dates, @events_by_date, @todos_by_date)}>
          <h3 class="text-sm font-semibold border-b border-base-300 pb-1">
            {Calendar.strftime(date, "%a %-d %b")}
          </h3>
          <div class="mt-2 space-y-1">
            <%= for event <- Map.get(@events_by_date, date, []) do %>
              <a
                :if={event.source == :google}
                href={event.external_url}
                target="_blank"
                rel="noopener noreferrer"
                class="block rounded px-3 py-2 bg-base-200"
              >
                <span class="font-medium">{event.title}</span>
                <span :if={event.start_time} class="text-xs opacity-60 ml-2">{event.start_time}</span>
              </a>
              <.link
                :if={event.source != :google}
                navigate={~p"/calendar/#{event}/edit"}
                class="block rounded px-3 py-2 bg-base-200"
              >
                <span class="font-medium">{event.title}</span>
                <span :if={event.start_time} class="text-xs opacity-60 ml-2">{event.start_time}</span>
              </.link>
            <% end %>
            <.link
              :for={todo <- Map.get(@todos_by_date, date, [])}
              navigate={~p"/todos/#{todo.todo_list_id}"}
              class="block rounded px-3 py-2 bg-primary text-primary-content"
            >
              <.icon name="hero-check-circle" class="size-4 align-text-bottom" /> {todo.title}
            </.link>
          </div>
        </section>
        <p
          :if={agenda_dates(@grid_dates, @events_by_date, @todos_by_date) == []}
          class="text-sm opacity-60"
        >
          {gettext("Nothing scheduled in this period.")}
        </p>
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
    end

    members = Households.list_household_members(scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Calendar"))
     |> assign(:today, Date.utc_today())
     |> assign(:members, members)
     |> assign(:member_colors, member_colors(members))
     |> assign(:expanded_dates, MapSet.new())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    month = parse_month(params["month"])
    grid_dates = grid_dates(month)

    socket =
      socket
      |> assign(:month, month)
      |> assign(:grid_dates, grid_dates)
      |> assign(
        :events_by_date,
        Enum.group_by(
          Events.list_events(
            socket.assigns.current_scope,
            List.first(grid_dates),
            List.last(grid_dates)
          ),
          & &1.date
        )
      )
      |> assign(
        :todos_by_date,
        Enum.group_by(
          Todos.list_due_items(
            socket.assigns.current_scope,
            List.first(grid_dates),
            List.last(grid_dates)
          ),
          & &1.due_date
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({type, %TodoItem{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, assign(socket, :todos_by_date, reload_todos(socket))}
  end

  def handle_info({type, _event}, socket) when type in [:created, :updated, :deleted] do
    {:noreply,
     socket
     |> assign(:events_by_date, reload_events(socket))
     |> assign(:todos_by_date, reload_todos(socket))}
  end

  @impl true
  def handle_event("toggle_day", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        expanded_dates =
          if MapSet.member?(socket.assigns.expanded_dates, date) do
            MapSet.delete(socket.assigns.expanded_dates, date)
          else
            MapSet.put(socket.assigns.expanded_dates, date)
          end

        {:noreply, assign(socket, :expanded_dates, expanded_dates)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp reload_events(socket) do
    grid_dates = socket.assigns.grid_dates

    Events.list_events(
      socket.assigns.current_scope,
      List.first(grid_dates),
      List.last(grid_dates)
    )
    |> Enum.group_by(& &1.date)
  end

  defp reload_todos(socket) do
    grid_dates = socket.assigns.grid_dates

    Todos.list_due_items(
      socket.assigns.current_scope,
      List.first(grid_dates),
      List.last(grid_dates)
    )
    |> Enum.group_by(& &1.due_date)
  end

  defp visible_events(events_by_date, date, expanded_dates) do
    events = Map.get(events_by_date, date, [])
    if MapSet.member?(expanded_dates, date), do: events, else: Enum.take(events, 3)
  end

  defp agenda_dates(dates, events_by_date, todos_by_date) do
    Enum.filter(dates, &(Map.has_key?(events_by_date, &1) or Map.has_key?(todos_by_date, &1)))
  end

  defp event_classes(%{source: :google}),
    do: "block truncate rounded px-1 py-0.5 text-left text-base-content bg-base-300"

  defp event_classes(_event), do: "block truncate rounded px-1 py-0.5 text-left text-white"

  defp parse_month(nil), do: Date.beginning_of_month(Date.utc_today())

  defp parse_month(month_string) do
    case Date.from_iso8601(month_string) do
      {:ok, date} -> Date.beginning_of_month(date)
      {:error, _} -> Date.beginning_of_month(Date.utc_today())
    end
  end

  # `month` is always already the 1st of its month, so stepping via a fixed
  # day count (e.g. +15) doesn't reliably cross the boundary — a 31-day
  # month needs +31, a 28-day one only +28. Going through the *end* of the
  # month (for +1) or a single day before the 1st (for -1) always lands on
  # the right month regardless of its length.
  defp shift_month(month, 1), do: Date.add(Date.end_of_month(month), 1)
  defp shift_month(month, -1), do: month |> Date.add(-1) |> Date.beginning_of_month()

  # Pads a month's dates out to full Monday-Sunday weeks, so the grid never
  # shows a partial first/last row.
  defp grid_dates(month) do
    last_day = Date.end_of_month(month)
    grid_start = Date.add(month, -(Date.day_of_week(month) - 1))
    grid_end = Date.add(last_day, 7 - Date.day_of_week(last_day))

    Date.range(grid_start, grid_end) |> Enum.to_list()
  end

  # Stable color-slot assignment by alphabetical order among the
  # household's members — same "color follows the entity, never its rank"
  # rule as the dashboard's category-breakdown chart, reusing the same
  # validated `--series-*` palette rather than inventing a second one.
  defp member_colors(members) do
    members
    |> Enum.with_index(1)
    |> Map.new(fn {member, index} -> {member.id, color_for_slot(index)} end)
  end

  defp color_for_slot(index) when index <= 8, do: "var(--series-#{index})"
  defp color_for_slot(_index), do: "var(--series-other)"

  defp member_color(_member_colors, nil), do: "var(--color-base-300)"

  defp member_color(member_colors, user_id),
    do: Map.get(member_colors, user_id, "var(--color-base-300)")

  defp event_color(_member_colors, %{source: :google}), do: "var(--color-base-300)"
  defp event_color(member_colors, event), do: member_color(member_colors, event.user_id)

  defp display_name(user), do: user.name || user.email

  # Elixir's Calendar.strftime/3 has no built-in locale awareness — "%B"
  # always renders English month names — so the month names are routed
  # through gettext explicitly via the `:month_names` callback instead.
  defp month_label(month), do: Calendar.strftime(month, "%B %Y", month_names: &month_name/1)

  defp month_name(month_number), do: Enum.at(month_names(), month_number - 1)

  defp month_names do
    [
      gettext("January"),
      gettext("February"),
      gettext("March"),
      gettext("April"),
      gettext("May"),
      gettext("June"),
      gettext("July"),
      gettext("August"),
      gettext("September"),
      gettext("October"),
      gettext("November"),
      gettext("December")
    ]
  end

  defp weekday_labels do
    [
      gettext("Mon"),
      gettext("Tue"),
      gettext("Wed"),
      gettext("Thu"),
      gettext("Fri"),
      gettext("Sat"),
      gettext("Sun")
    ]
  end
end
