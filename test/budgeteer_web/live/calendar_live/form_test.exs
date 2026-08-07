defmodule BudgeteerWeb.CalendarLive.FormTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.EventsFixtures
  import Budgeteer.HouseholdsFixtures, only: [second_household_member_fixture: 1]

  alias Budgeteer.Events

  setup :register_and_log_in_user

  describe "new event" do
    test "pre-fills the date from the ?date= query param", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/calendar/new?date=2026-08-20")
      assert html =~ ~s(value="2026-08-20")
    end

    test "creates an event and redirects to the calendar", %{conn: conn, scope: scope} do
      {:ok, live, _html} = live(conn, ~p"/calendar/new?date=2026-08-20")

      form = form(live, "#event-form", event: %{title: "Piano recital", date: "2026-08-20"})
      render_submit(form)

      assert_redirect(live, ~p"/calendar")
      assert [event] = Events.list_events(scope, ~D[2026-08-01], ~D[2026-08-31])
      assert event.title == "Piano recital"
    end

    test "assigning the event to a household member stores it", %{conn: conn, scope: scope} do
      member = second_household_member_fixture(scope.user)
      {:ok, live, _html} = live(conn, ~p"/calendar/new?date=2026-08-20")

      form(live, "#event-form",
        event: %{title: "Football practice", date: "2026-08-20", user_id: member.id}
      )
      |> render_submit()

      assert [event] = Events.list_events(scope, ~D[2026-08-01], ~D[2026-08-31])
      assert event.user_id == member.id
    end

    test "shows a validation error for a blank title", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/calendar/new?date=2026-08-20")

      html =
        form(live, "#event-form", event: %{title: "", date: "2026-08-20"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end

  describe "edit event" do
    test "renders imported Google events as disabled and read-only", %{conn: conn, scope: scope} do
      assert {:ok, 1} =
               Events.replace_google_events(scope, "primary", [
                 %{
                   "id" => "google-event",
                   "summary" => "Imported",
                   "start" => %{"date" => "2026-08-20"},
                   "end" => %{"date" => "2026-08-21"}
                 }
               ])

      [event] = Events.list_events(scope, ~D[2026-08-01], ~D[2026-08-31])
      {:ok, live, html} = live(conn, ~p"/calendar/#{event}/edit")

      assert html =~ "read-only"
      assert has_element?(live, "#event_title[disabled]")
      refute has_element?(live, "button", "Save Event")
    end

    test "updates an event", %{conn: conn, scope: scope} do
      event = event_fixture(scope, %{title: "Old title"})
      {:ok, live, _html} = live(conn, ~p"/calendar/#{event}/edit")

      form(live, "#event-form", event: %{title: "New title"}) |> render_submit()

      assert_redirect(live, ~p"/calendar")
      assert Events.get_event!(scope, event.id).title == "New title"
    end

    test "deletes an event via the confirmed delete action", %{conn: conn, scope: scope} do
      event = event_fixture(scope)
      {:ok, live, _html} = live(conn, ~p"/calendar/#{event}/edit")

      live |> element("a", "Delete") |> render_click()

      assert_redirect(live, ~p"/calendar")
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(scope, event.id) end
    end
  end
end
