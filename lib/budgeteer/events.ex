defmodule Budgeteer.Events do
  @moduledoc """
  The Events context — household calendar events, optionally assigned to
  one member (for color-coding) or left unassigned (a whole-household
  event). Named `Events`, not `Calendar` (even though the user-facing
  feature is "the calendar", routed at `/calendar` via `CalendarLive.*`) —
  `Budgeteer.Calendar` would shadow Elixir's own stdlib `Calendar` module,
  breaking `Calendar.strftime/2` (used to render the month header) the
  moment `CalendarLive` aliased it. Hand-written like `Groceries`/`Meals`
  rather than `phx.gen.live`'d: the month-grid view doesn't fit the
  generator's navigate-to-a-list-page CRUD assumption.
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo

  alias Budgeteer.Events.Event
  alias Budgeteer.Households.Scope

  @doc """
  Subscribes to scoped notifications about event changes.

  The broadcasted messages match the pattern:

    * {:created, %Event{}}
    * {:updated, %Event{}}
    * {:deleted, %Event{}}

  """
  def subscribe_events(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{scope.user.household_id}:events")
  end

  defp broadcast_event(household_id, message) do
    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{household_id}:events", message)
  end

  @doc """
  Returns the household's events with `date` between `from` and `to`
  (inclusive), ordered by date then start time — for a month grid, `from`/
  `to` should already include the leading/trailing days from adjacent
  months that the grid pads out to a full week.
  """
  def list_events(%Scope{} = scope, %Date{} = from, %Date{} = to) do
    Repo.all(
      from e in Event,
        where: e.household_id == ^scope.user.household_id and e.date >= ^from and e.date <= ^to,
        order_by: [asc: e.date, asc: e.start_time]
    )
  end

  @doc """
  Gets a single event, scoped to the household.
  """
  def get_event!(%Scope{} = scope, id) do
    Repo.get_by!(Event, id: id, household_id: scope.user.household_id)
  end

  @doc """
  Creates an event, attributed to the scoped user as its creator.
  """
  def create_event(%Scope{} = scope, attrs) do
    with {:ok, event = %Event{}} <-
           %Event{}
           |> Event.changeset(attrs, scope)
           |> Ecto.Changeset.put_change(:created_by_id, scope.user.id)
           |> Repo.insert() do
      broadcast_event(event.household_id, {:created, event})
      {:ok, event}
    end
  end

  @doc """
  Updates an event.
  """
  def update_event(%Scope{} = scope, %Event{} = event, attrs) do
    true = event.household_id == scope.user.household_id

    with {:ok, event = %Event{}} <-
           event
           |> Event.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_event(event.household_id, {:updated, event})
      {:ok, event}
    end
  end

  @doc """
  Deletes an event.
  """
  def delete_event(%Scope{} = scope, %Event{} = event) do
    true = event.household_id == scope.user.household_id

    with {:ok, event = %Event{}} <- Repo.delete(event) do
      broadcast_event(event.household_id, {:deleted, event})
      {:ok, event}
    end
  end

  @doc """
  Returns a changeset for tracking event changes.
  """
  def change_event(%Scope{} = scope, %Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs, scope)
  end
end
