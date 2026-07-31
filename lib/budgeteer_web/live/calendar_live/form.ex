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

      <.form for={@form} id="event-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:date]} type="date" label="Date" />
        <.input field={@form[:start_time]} type="time" label="Start time" />
        <.input field={@form[:end_time]} type="time" label="End time" />
        <.input
          field={@form[:user_id]}
          type="select"
          label="For"
          prompt="Whole household"
          options={Enum.map(@members, &{display_name(&1), &1.id})}
        />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <footer class="flex items-center gap-2">
          <.button phx-disable-with="Saving..." variant="primary">Save Event</.button>
          <.button navigate={~p"/calendar"}>Cancel</.button>
          <.link
            :if={@live_action == :edit}
            phx-click={JS.push("delete")}
            data-confirm="Are you sure you want to delete this event?"
            class="ml-auto text-error"
          >
            Delete
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
    |> assign(:page_title, "Edit Event")
    |> assign(:event, event)
    |> assign(:form, to_form(Events.change_event(scope, event)))
  end

  defp apply_action(socket, :new, params) do
    scope = socket.assigns.current_scope
    event = %Event{household_id: scope.user.household_id, date: prefill_date(params["date"])}

    socket
    |> assign(:page_title, "New Event")
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
    {:ok, _} = Events.delete_event(socket.assigns.current_scope, socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Event deleted successfully")
     |> push_navigate(to: ~p"/calendar")}
  end

  defp save_event(socket, :edit, event_params) do
    case Events.update_event(socket.assigns.current_scope, socket.assigns.event, event_params) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event updated successfully")
         |> push_navigate(to: ~p"/calendar")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_event(socket, :new, event_params) do
    case Events.create_event(socket.assigns.current_scope, event_params) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event created successfully")
         |> push_navigate(to: ~p"/calendar")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp display_name(user), do: user.name || user.email
end
