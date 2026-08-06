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
  alias Budgeteer.Households.User

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
  Returns the household's events on one specific date, by household id
  (no scope) — same "background job, no user context" precedent as
  `Households.list_household_emails/1`, used by
  `Budgeteer.DailySummary.Worker`.
  """
  def list_events_for_household(household_id, %Date{} = date) do
    Repo.all(
      from e in Event,
        where: e.household_id == ^household_id and e.date == ^date,
        order_by: [asc: e.start_time]
    )
  end

  @doc "Replaces one user's imported Google events for a calendar."
  def replace_google_events(%Scope{} = scope, calendar_id, google_events)
      when is_binary(calendar_id) and is_list(google_events) do
    attrs =
      google_events
      |> Enum.filter(&(&1["status"] != "cancelled"))
      |> Enum.flat_map(fn event ->
        case google_event_attrs(event, scope, calendar_id) do
          {:ok, attrs} -> [attrs]
          :skip -> []
        end
      end)

    external_ids = Enum.map(attrs, & &1.external_id)

    with {:ok, {imported, stale}} <-
           Repo.transaction(fn ->
             imported =
               Enum.map(attrs, fn attrs ->
                 %Event{}
                 |> Event.google_changeset(attrs, scope)
                 |> Repo.insert!(
                   on_conflict:
                     {:replace,
                      [
                        :title,
                        :description,
                        :date,
                        :start_time,
                        :end_time,
                        :external_url,
                        :updated_at
                      ]},
                   conflict_target:
                     {:unsafe_fragment,
                      "(source, user_id, external_calendar_id, external_id) WHERE source = 'google' AND external_id IS NOT NULL"},
                   returning: true
                 )
               end)

             stale_query =
               from e in Event,
                 where:
                   e.household_id == ^scope.user.household_id and
                     e.source == :google and
                     e.user_id == ^scope.user.id and
                     e.external_calendar_id == ^calendar_id

             stale_query =
               if external_ids == [],
                 do: stale_query,
                 else: where(stale_query, [e], e.external_id not in ^external_ids)

             stale = Repo.all(stale_query)
             Repo.delete_all(stale_query)
             {imported, stale}
           end) do
      Enum.each(imported, &broadcast_event(scope.user.household_id, {:updated, &1}))
      Enum.each(stale, &broadcast_event(scope.user.household_id, {:deleted, &1}))
      {:ok, length(imported)}
    end
  end

  @doc "Deletes the current user's imported Google events when disconnecting."
  def delete_google_events(%Scope{} = scope) do
    query =
      from e in Event,
        where:
          e.household_id == ^scope.user.household_id and
            e.source == :google and
            e.user_id == ^scope.user.id

    events = Repo.all(query)
    {count, _} = Repo.delete_all(query)
    Enum.each(events, &broadcast_event(scope.user.household_id, {:deleted, &1}))
    {:ok, count}
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
    changeset =
      %Event{}
      |> Event.changeset(attrs, scope)
      |> validate_user_scope(scope)
      |> Ecto.Changeset.put_change(:created_by_id, scope.user.id)

    with {:ok, event = %Event{}} <-
           Repo.insert(changeset) do
      broadcast_event(event.household_id, {:created, event})
      {:ok, event}
    end
  end

  @doc """
  Updates an event.
  """
  def update_event(%Scope{} = scope, %Event{} = event, attrs) do
    true = event.household_id == scope.user.household_id

    if event.source == :google do
      {:error, :read_only}
    else
      changeset = event |> Event.changeset(attrs, scope) |> validate_user_scope(scope)

      with {:ok, event = %Event{}} <- Repo.update(changeset) do
        broadcast_event(event.household_id, {:updated, event})
        {:ok, event}
      end
    end
  end

  @doc """
  Deletes an event.
  """
  def delete_event(%Scope{} = scope, %Event{} = event) do
    true = event.household_id == scope.user.household_id

    if event.source == :google do
      {:error, :read_only}
    else
      with {:ok, event = %Event{}} <- Repo.delete(event) do
        broadcast_event(event.household_id, {:deleted, event})
        {:ok, event}
      end
    end
  end

  @doc """
  Returns a changeset for tracking event changes.
  """
  def change_event(%Scope{} = scope, %Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs, scope)
  end

  defp validate_user_scope(changeset, %Scope{} = scope) do
    case Ecto.Changeset.get_field(changeset, :user_id) do
      nil ->
        changeset

      user_id ->
        query =
          from u in User,
            where: u.id == ^user_id and u.household_id == ^scope.user.household_id

        if Repo.exists?(query) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :user_id, "does not belong to this household")
        end
    end
  end

  defp google_event_attrs(event, %Scope{} = scope, calendar_id) do
    with external_id when is_binary(external_id) <- event["id"],
         {:ok, start} <- google_datetime(event["start"]),
         {:ok, finish} <- google_datetime(event["end"]) do
      {:ok,
       %{
         title: event["summary"] || "Untitled event",
         description: event["description"],
         date: start.date,
         start_time: start.time,
         end_time: finish.time,
         user_id: scope.user.id,
         external_calendar_id: calendar_id,
         external_id: external_id,
         external_url: event["htmlLink"]
       }}
    else
      _ -> :skip
    end
  end

  defp google_datetime(%{"date" => date}) when is_binary(date) do
    with {:ok, date} <- Date.from_iso8601(date), do: {:ok, %{date: date, time: nil}}
  end

  defp google_datetime(%{"dateTime" => date_time}) when is_binary(date_time) do
    with {:ok, date_time, _offset} <- DateTime.from_iso8601(date_time) do
      {:ok, %{date: DateTime.to_date(date_time), time: DateTime.to_time(date_time)}}
    end
  end

  defp google_datetime(_), do: :error
end
