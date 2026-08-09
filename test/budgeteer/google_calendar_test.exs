defmodule Budgeteer.GoogleCalendarTest do
  use Budgeteer.DataCase

  import Mox
  import Budgeteer.HouseholdsFixtures

  alias Budgeteer.GoogleCalendar
  alias Budgeteer.Events

  setup :verify_on_exit!

  @google_event %{
    "id" => "event-1",
    "status" => "confirmed",
    "summary" => "Dentist",
    "description" => "Bring insurance card",
    "htmlLink" => "https://calendar.google.com/event-1",
    "start" => %{"dateTime" => "2026-08-10T09:00:00+01:00"},
    "end" => %{"dateTime" => "2026-08-10T10:00:00+01:00"}
  }

  test "connects a user and imports primary calendar events" do
    user = user_fixture()

    expect(Budgeteer.GoogleCalendar.ClientMock, :exchange_code, fn "code", _redirect_uri ->
      {:ok, %{"refresh_token" => "refresh-token", "access_token" => "access-token"}}
    end)

    expect(Budgeteer.GoogleCalendar.ClientMock, :list_calendars, fn "access-token" ->
      {:ok, [%{"id" => "primary", "summary" => "My calendar", "primary" => true}]}
    end)

    expect(Budgeteer.GoogleCalendar.ClientMock, :refresh_access_token, fn "refresh-token" ->
      {:ok, %{"access_token" => "access-token"}}
    end)

    expect(Budgeteer.GoogleCalendar.ClientMock, :list_events, fn
      "access-token", "primary", _time_min, _time_max -> {:ok, [@google_event]}
    end)

    assert {:ok, 1} = GoogleCalendar.connect_user(user, "code", "http://localhost/callback")

    scope = household_scope_fixture(user)

    assert [%{title: "Dentist", source: :google, external_id: "event-1"}] =
             Events.list_events(scope, ~D[2026-08-01], ~D[2026-08-31])

    reloaded = Budgeteer.Households.get_user!(user.id)
    assert reloaded.google_calendar["refresh_token"] == "refresh-token"
  end

  test "a later sync removes events deleted from Google" do
    user = user_fixture()
    scope = household_scope_fixture(user)

    {:ok, _} = Budgeteer.Households.save_google_calendar(user, "refresh-token", ["primary"])

    expect(Budgeteer.GoogleCalendar.ClientMock, :refresh_access_token, fn "refresh-token" ->
      {:ok, %{"access_token" => "access-token"}}
    end)

    expect(Budgeteer.GoogleCalendar.ClientMock, :list_calendars, fn "access-token" ->
      {:ok, [%{"id" => "primary", "summary" => "My calendar", "primary" => true}]}
    end)

    expect(Budgeteer.GoogleCalendar.ClientMock, :list_events, fn
      "access-token", "primary", _time_min, _time_max -> {:ok, [@google_event]}
    end)

    assert {:ok, 1} = GoogleCalendar.sync_user(Budgeteer.Households.get_user!(user.id))

    expect(Budgeteer.GoogleCalendar.ClientMock, :refresh_access_token, fn "refresh-token" ->
      {:ok, %{"access_token" => "access-token"}}
    end)

    expect(Budgeteer.GoogleCalendar.ClientMock, :list_events, fn
      "access-token", "primary", _time_min, _time_max -> {:ok, []}
    end)

    assert {:ok, 0} = GoogleCalendar.sync_user(Budgeteer.Households.get_user!(user.id))
    assert Events.list_events(scope, ~D[2026-08-01], ~D[2026-08-31]) == []
  end

  test "imports long descriptions and Google links" do
    scope = household_scope_fixture()
    long_description = String.duplicate("details ", 80)
    long_url = "https://calendar.google.com/event?" <> String.duplicate("parameter=value&", 30)

    assert {:ok, 1} =
             Events.replace_google_events(scope, "primary", [
               %{
                 "id" => "long-event",
                 "summary" => "Long event",
                 "description" => long_description,
                 "htmlLink" => long_url,
                 "start" => %{"date" => "2026-08-20"},
                 "end" => %{"date" => "2026-08-21"}
               }
             ])

    [event] = Events.list_events(scope, ~D[2026-08-01], ~D[2026-08-31])
    assert event.description == long_description
    assert event.external_url == long_url
  end

  test "disconnecting removes only the current user's imported events" do
    owner = user_fixture()
    member = second_household_member_fixture(owner)
    owner_scope = household_scope_fixture(owner)
    member_scope = household_scope_fixture(member)

    assert {:ok, _} =
             Events.replace_google_events(owner_scope, "primary", [@google_event])

    assert [%{user_id: owner_id, source: :google}] =
             Events.list_events(owner_scope, ~D[2026-08-01], ~D[2026-08-31])

    assert owner_id == owner.id

    assert {:ok, _} =
             Events.replace_google_events(member_scope, "primary", [
               Map.put(@google_event, "id", "member-event")
             ])

    assert {:ok, 1} = Events.delete_google_events(owner_scope)

    assert [%{external_id: "member-event"}] =
             Events.list_events(owner_scope, ~D[2026-08-01], ~D[2026-08-31])

    assert [%{external_id: "member-event"}] =
             Events.list_events(member_scope, ~D[2026-08-01], ~D[2026-08-31])
  end
end
