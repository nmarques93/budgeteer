defmodule BudgeteerWeb.CalendarLive.Form do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Events
  alias Budgeteer.Events.Event
  alias Budgeteer.Households

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>{@page_title}</.header>

      <p :if={@event.source == :google} class="alert alert-info mb-4">
        {gettext("This event comes from Google Calendar and is read-only here.")}
      </p>

      <.form for={@form} id="event-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:title]}
          type="text"
          label={gettext("Title")}
          disabled={@event.source == :google}
        />
        <.input
          field={@form[:date]}
          type="date"
          label={gettext("Date")}
          disabled={@event.source == :google}
        />
        <.input
          field={@form[:start_time]}
          type="time"
          label={gettext("Start time")}
          disabled={@event.source == :google}
        />
        <.input
          field={@form[:end_time]}
          type="time"
          label={gettext("End time")}
          disabled={@event.source == :google}
        />
        <.input
          field={@form[:user_id]}
          type="select"
          label={gettext("For")}
          prompt={gettext("Whole household")}
          options={Enum.map(@members, &{display_name(&1), &1.id})}
          disabled={@event.source == :google}
        />
        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          disabled={@event.source == :google}
        />
        <footer class="flex items-center gap-2">
          <.button
            :if={@event.source != :google}
            phx-disable-with={gettext("Saving...")}
            variant="primary"
          >
            {gettext("Save Event")}
          </.button>
          <.button navigate={~p"/calendar"}>{gettext("Cancel")}</.button>
          <.link
            :if={@live_action == :edit and @event.source != :google}
            phx-click={JS.push("delete")}
            data-confirm={gettext("Are you sure you want to delete this event?")}
            class="ml-auto text-error"
          >
            {gettext("Delete")}
          </.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:members, Households.list_household_members(scope))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope
    event = Events.get_event!(scope, id)

    socket
    |> assign(:page_title, gettext("Edit Event"))
    |> assign(:event, event)
    |> assign(:form, to_form(Events.change_event(scope, event)))
  end

  defp apply_action(socket, :new, params) do
    scope = socket.assigns.current_scope
    event = %Event{household_id: scope.user.household_id, date: prefill_date(params["date"])}

    socket
    |> assign(:page_title, gettext("New Event"))
    |> assign(:event, event)
    |> assign(:form, to_form(Events.change_event(scope, event)))
  end

  defp prefill_date(nil), do: Date.utc_today()

  defp prefill_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> Date.utc_today()
    end
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    changeset =
      Events.change_event(socket.assigns.current_scope, socket.assigns.event, event_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"event" => event_params}, socket) do
    save_event(socket, socket.assigns.live_action, event_params)
  end

  def handle_event("delete", _params, socket) do
    case Events.delete_event(socket.assigns.current_scope, socket.assigns.event) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Event deleted successfully"))
         |> push_navigate(to: ~p"/calendar")}

      {:error, :read_only} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Google Calendar events are read-only."))
         |> push_navigate(to: ~p"/calendar")}
    end
  end

  defp save_event(socket, :edit, event_params) do
    case Events.update_event(socket.assigns.current_scope, socket.assigns.event, event_params) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Event updated successfully"))
         |> push_navigate(to: ~p"/calendar")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :read_only} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Google Calendar events are read-only."))
         |> push_navigate(to: ~p"/calendar")}
    end
  end

  defp save_event(socket, :new, event_params) do
    case Events.create_event(socket.assigns.current_scope, event_params) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Event created successfully"))
         |> push_navigate(to: ~p"/calendar")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp display_name(user), do: user.name || user.email
end
