defmodule BudgeteerWeb.TodoListLive.ShowTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.TodosFixtures

  alias Budgeteer.Todos

  setup :register_and_log_in_user

  test "adds, completes, edits, reorders, and deletes tasks", %{conn: conn, scope: scope} do
    todo_list = todo_list_fixture(scope, %{name: "House tasks"})
    {:ok, live, html} = live(conn, ~p"/todos/#{todo_list}")
    assert html =~ "No tasks yet."

    live
    |> form("#todo-item-form", todo_item: %{title: "Book dentist appointment"})
    |> render_submit()

    assert has_element?(live, "#todo-items", "Book dentist appointment")
    item = hd(Todos.list_items(scope, todo_list))

    live |> element("input[phx-value-id='#{item.id}'][type='checkbox']") |> render_click()
    assert has_element?(live, "#todo-items p.line-through", "Book dentist appointment")

    live |> element("button[phx-value-id='#{item.id}'][aria-label='Edit task']") |> render_click()

    live
    |> form("#todo-item-edit-#{item.id}",
      todo_item_edit: %{title: "Call dentist", notes: "Before Friday"}
    )
    |> render_submit()

    assert has_element?(live, "#todo-items", "Call dentist")

    live
    |> element("button[phx-value-id='#{item.id}'][aria-label='Delete task']")
    |> render_click()

    refute has_element?(live, "#todo-items", "Call dentist")
  end
end
