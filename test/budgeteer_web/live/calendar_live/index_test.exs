defmodule BudgeteerWeb.CalendarLive.IndexTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.EventsFixtures
  import Budgeteer.HouseholdsFixtures, only: [second_household_member_fixture: 1]

  setup :register_and_log_in_user

  test "renders the current month by default", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/calendar")
    assert html =~ Calendar.strftime(Date.utc_today(), "%B %Y")
  end

  test "shows an event that falls within the visible month grid", %{conn: conn, scope: scope} do
    event_fixture(scope, %{title: "Dentist appointment", date: Date.utc_today()})

    {:ok, _live, html} = live(conn, ~p"/calendar")
    assert html =~ "Dentist appointment"
  end

  test "expands a day with more than three events", %{conn: conn, scope: scope} do
    for index <- 1..4 do
      event_fixture(scope, %{
        title: "Event #{index}",
        date: Date.utc_today(),
        start_time: Time.add(~T[09:00:00], index * 3600)
      })
    end

    {:ok, live, html} = live(conn, ~p"/calendar")
    assert html =~ "+1 more"
    refute html =~ "Event 4"

    html = live |> element("button", "+1 more") |> render_click()
    assert html =~ "Event 4"
    assert html =~ "Show less"
  end

  test "the next/previous month links navigate and change the visible events", %{
    conn: conn,
    scope: scope
  } do
    today = Date.beginning_of_month(Date.utc_today())
    next_month = Date.add(Date.end_of_month(today), 15)

    event_fixture(scope, %{title: "Current month event", date: today})
    event_fixture(scope, %{title: "Next month event", date: next_month})

    {:ok, live, html} = live(conn, ~p"/calendar")
    assert html =~ "Current month event"
    refute html =~ "Next month event"

    html = live |> element("[aria-label='Next month']") |> render_click()
    assert html =~ "Next month event"
    refute html =~ "Current month event"

    html = live |> element("[aria-label='Previous month']") |> render_click()
    assert html =~ "Current month event"
    refute html =~ "Next month event"
  end

  test "lists household members in the legend, colored", %{conn: conn, scope: scope} do
    member = second_household_member_fixture(scope.user)

    {:ok, _live, html} = live(conn, ~p"/calendar")
    assert html =~ "Whole household"
    assert html =~ member.email
  end

  test "updates live via PubSub when an event is created elsewhere for the same household", %{
    conn: conn,
    scope: scope
  } do
    {:ok, live, html} = live(conn, ~p"/calendar")
    refute html =~ "Just added"

    event_fixture(scope, %{title: "Just added", date: Date.utc_today()})

    assert render(live) =~ "Just added"
  end
end
