defmodule BudgeteerWeb.TodoListLiveTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.TodosFixtures

  setup :register_and_log_in_user

  test "lists TODO lists and creates a list", %{conn: conn} do
    {:ok, live, html} = live(conn, ~p"/todos")
    assert html =~ "TODO lists"

    {:ok, form_live, _html} =
      live
      |> element("a", "New list")
      |> render_click()
      |> follow_redirect(conn, ~p"/todos/new")

    assert form_live
           |> form("#todo-list-form", todo_list: %{name: "Home tasks"})
           |> render_submit()

    assert_redirect(form_live, ~p"/todos")
  end

  test "shows owner list controls", %{conn: conn, scope: scope} do
    todo_list_fixture(scope, %{name: "House tasks"})
    {:ok, _live, html} = live(conn, ~p"/todos")
    assert html =~ "House tasks"
    assert html =~ "Delete"
  end
end
