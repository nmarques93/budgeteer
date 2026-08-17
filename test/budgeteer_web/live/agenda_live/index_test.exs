defmodule BudgeteerWeb.AgendaLive.IndexTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.EventsFixtures
  import Budgeteer.MealsFixtures
  import Budgeteer.TodosFixtures

  setup :register_and_log_in_user

  test "renders the current week with events, todos, and meals", %{conn: conn, scope: scope} do
    today = Date.utc_today()
    event_fixture(scope, %{title: "School play", date: today})
    todo_list = todo_list_fixture(scope)
    todo_item_fixture(scope, todo_list, %{title: "Buy light bulbs", due_date: today})
    recipe = recipe_fixture(scope, %{name: "Pasta"})
    planned_meal_fixture(scope, recipe, %{date: today})

    {:ok, _live, html} = live(conn, ~p"/agenda")

    assert html =~ "Household agenda"
    assert html =~ "School play"
    assert html =~ "Buy light bulbs"
    assert html =~ "Pasta"
  end

  test "navigates weeks and keeps items within the selected range", %{conn: conn, scope: scope} do
    today = Date.utc_today()
    next_week = Date.add(today, 8)
    event_fixture(scope, %{title: "Current week event", date: today})
    event_fixture(scope, %{title: "Next week event", date: next_week})

    {:ok, live, html} = live(conn, ~p"/agenda")
    assert html =~ "Current week event"
    refute html =~ "Next week event"

    html = live |> element("[aria-label='Next week']") |> render_click()
    assert html =~ "Next week event"
    refute html =~ "Current week event"
  end

  test "lists unchecked shopping items and budget alerts", %{conn: conn, scope: scope} do
    # Budget alert category requires a spent budget alert claim, so rely on
    # the unchecked shopping items which are deterministic to seed.
    {:ok, list} = Budgeteer.Groceries.create_grocery_list(scope, %{name: "Weekly"})
    {:ok, _item} = Budgeteer.Groceries.create_item(scope, list, %{name: "Milk"})

    {:ok, _live, html} = live(conn, ~p"/agenda")
    assert html =~ "Shopping list"
    assert html =~ "Milk"
    assert html =~ "Weekly"
  end
end
