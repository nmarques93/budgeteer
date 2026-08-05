defmodule Budgeteer.EventsTest do
  use Budgeteer.DataCase

  alias Budgeteer.Events
  alias Budgeteer.Events.Event

  import Budgeteer.HouseholdsFixtures
  import Budgeteer.EventsFixtures

  describe "list_events/3" do
    test "returns only events within the date range, for the current household" do
      scope = household_scope_fixture()

      in_range = event_fixture(scope, %{title: "In range", date: ~D[2026-08-15]})
      _before = event_fixture(scope, %{title: "Before", date: ~D[2026-07-31]})
      _after = event_fixture(scope, %{title: "After", date: ~D[2026-09-01]})

      other_scope = household_scope_fixture()
      event_fixture(other_scope, %{title: "Other household", date: ~D[2026-08-15]})

      assert [event] = Events.list_events(scope, ~D[2026-08-01], ~D[2026-08-31])
      assert event.id == in_range.id
    end

    test "orders by date then start time" do
      scope = household_scope_fixture()

      late =
        event_fixture(scope, %{title: "Late", date: ~D[2026-08-15], start_time: ~T[18:00:00]})

      early =
        event_fixture(scope, %{title: "Early", date: ~D[2026-08-15], start_time: ~T[09:00:00]})

      next_day = event_fixture(scope, %{title: "Next day", date: ~D[2026-08-16]})

      assert [^early, ^late, ^next_day] =
               Events.list_events(scope, ~D[2026-08-01], ~D[2026-08-31])
    end
  end

  describe "list_events_for_household/2" do
    test "returns only events on that exact date, for that household" do
      scope = household_scope_fixture()
      today = event_fixture(scope, %{title: "Today", date: ~D[2026-08-15]})
      _other_day = event_fixture(scope, %{title: "Other day", date: ~D[2026-08-16]})

      other_scope = household_scope_fixture()
      event_fixture(other_scope, %{title: "Other household", date: ~D[2026-08-15]})

      assert [event] = Events.list_events_for_household(scope.user.household_id, ~D[2026-08-15])
      assert event.id == today.id
    end
  end

  describe "create_event/2" do
    test "creates an event owned by the household, attributed to its creator" do
      scope = household_scope_fixture()

      assert {:ok, %Event{} = event} =
               Events.create_event(scope, %{title: "Dentist", date: ~D[2026-08-20]})

      assert event.household_id == scope.user.household_id
      assert event.created_by_id == scope.user.id
    end

    test "requires a title and a date" do
      scope = household_scope_fixture()
      assert {:error, changeset} = Events.create_event(scope, %{})
      assert %{title: ["can't be blank"], date: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an end time that isn't after the start time" do
      scope = household_scope_fixture()

      assert {:error, changeset} =
               Events.create_event(scope, %{
                 title: "Bad times",
                 date: ~D[2026-08-20],
                 start_time: ~T[10:00:00],
                 end_time: ~T[09:00:00]
               })

      assert %{end_time: ["must be after the start time"]} = errors_on(changeset)
    end

    test "can be assigned to a specific household member" do
      owner = user_fixture()
      member = second_household_member_fixture(owner)
      scope = household_scope_fixture(owner)

      assert {:ok, event} =
               Events.create_event(scope, %{
                 title: "Piano lesson",
                 date: ~D[2026-08-20],
                 user_id: member.id
               })

      assert event.user_id == member.id
    end

    test "rejects assignment to a member from another household" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()

      assert {:error, changeset} =
               Events.create_event(scope, %{
                 title: "Private event",
                 date: ~D[2026-08-20],
                 user_id: other_scope.user.id
               })

      assert %{user_id: ["does not belong to this household"]} = errors_on(changeset)
    end
  end

  describe "update_event/3 and delete_event/2" do
    test "updates an event" do
      scope = household_scope_fixture()
      event = event_fixture(scope, %{title: "Old title"})

      assert {:ok, updated} = Events.update_event(scope, event, %{title: "New title"})
      assert updated.title == "New title"
    end

    test "deletes an event" do
      scope = household_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, _} = Events.delete_event(scope, event)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(scope, event.id) end
    end
  end

  describe "real-time sync" do
    test "create/update/delete broadcast to household subscribers" do
      scope = household_scope_fixture()
      Events.subscribe_events(scope)

      {:ok, event} = Events.create_event(scope, %{title: "Party", date: ~D[2026-08-20]})
      assert_receive {:created, %Event{id: id}} when id == event.id

      {:ok, event} = Events.update_event(scope, event, %{title: "Big party"})
      assert_receive {:updated, %Event{title: "Big party"}}

      {:ok, _} = Events.delete_event(scope, event)
      assert_receive {:deleted, %Event{id: id}} when id == event.id
    end
  end

  describe "household scoping" do
    test "get_event!/2, update_event/3, delete_event/2 don't leak across households" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      event = event_fixture(scope)

      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(other_scope, event.id) end

      assert_raise MatchError, fn ->
        Events.update_event(other_scope, event, %{title: "hijacked"})
      end

      assert_raise MatchError, fn -> Events.delete_event(other_scope, event) end
    end
  end
end
