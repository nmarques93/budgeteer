defmodule Budgeteer.TodosTest do
  use Budgeteer.DataCase

  alias Budgeteer.Todos

  import Budgeteer.HouseholdsFixtures
  import Budgeteer.TodosFixtures

  describe "lists" do
    test "lists are scoped and can be archived" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      list = todo_list_fixture(scope)
      other_list = todo_list_fixture(other_scope)

      assert [^list] = Todos.list_todo_lists(scope)
      assert [^other_list] = Todos.list_todo_lists(other_scope)

      assert {:ok, _} = Todos.archive_todo_list(scope, list)
      assert Todos.list_todo_lists(scope) == []
      assert [archived] = Todos.list_todo_lists(scope, archived: true)
      assert archived.id == list.id
    end

    test "members cannot archive or delete a list" do
      owner = user_fixture()
      member = second_household_member_fixture(owner)
      scope = household_scope_fixture(member)
      list = todo_list_fixture(scope)

      assert {:error, :forbidden} = Todos.archive_todo_list(scope, list)
      assert {:error, :forbidden} = Todos.delete_todo_list(scope, list)
    end
  end

  describe "items" do
    test "creates, toggles, updates, and deletes items" do
      scope = household_scope_fixture()
      todo_list = todo_list_fixture(scope)
      item = todo_item_fixture(scope, todo_list, %{notes: "Call soon"})

      assert item.position == 0
      assert [^item] = Todos.list_items(scope, todo_list)

      assert {:ok, completed} = Todos.toggle_item(scope, item)
      assert completed.completed
      assert completed.completed_by_id == scope.user.id

      assert {:ok, updated} = Todos.update_item(scope, completed, %{title: "Call dentist"})
      assert updated.title == "Call dentist"

      assert {:ok, _} = Todos.delete_item(scope, updated)
      assert Todos.list_items(scope, todo_list) == []
    end

    test "assigns an item to a household member with a priority" do
      owner = user_fixture()
      member = second_household_member_fixture(owner, %{name: "Alex"})
      scope = household_scope_fixture(owner)
      todo_list = todo_list_fixture(scope)

      assert {:ok, item} =
               Todos.create_item(scope, todo_list, %{
                 title: "Pick up keys",
                 assignee_id: member.id,
                 priority: :high
               })

      assert item.assignee_id == member.id
      assert item.priority == :high
      assert item.assignee.email == member.email
    end

    test "creates the next occurrence when a recurring task is completed" do
      scope = household_scope_fixture()
      todo_list = todo_list_fixture(scope)
      due_date = Date.utc_today()
      item = todo_item_fixture(scope, todo_list, %{due_date: due_date, recurrence: :weekly})

      assert {:ok, completed} = Todos.toggle_item(scope, item)
      assert completed.completed

      [next_item] =
        scope
        |> Todos.list_items(todo_list)
        |> Enum.reject(&(&1.id == completed.id))

      assert next_item.title == item.title
      assert next_item.recurrence == :weekly
      assert next_item.due_date == Date.add(due_date, 7)
      refute next_item.completed
    end

    test "requires a due date for recurring tasks" do
      scope = household_scope_fixture()
      todo_list = todo_list_fixture(scope)

      assert {:error, changeset} =
               Todos.create_item(scope, todo_list, %{title: "Recurring", recurrence: :daily})

      assert %{due_date: ["is required for recurring tasks"]} = errors_on(changeset)
    end

    test "rejects an assignee from another household" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      todo_list = todo_list_fixture(scope)

      assert {:error, changeset} =
               Todos.create_item(scope, todo_list, %{
                 title: "Private task",
                 assignee_id: other_scope.user.id
               })

      assert %{assignee_id: ["does not belong to this household"]} = errors_on(changeset)
    end

    test "moves items up and down" do
      scope = household_scope_fixture()
      todo_list = todo_list_fixture(scope)
      first = todo_item_fixture(scope, todo_list, %{title: "First"})
      second = todo_item_fixture(scope, todo_list, %{title: "Second"})

      assert {:ok, _} = Todos.move_item(scope, second, :up)
      assert [moved_first, moved_second] = Todos.list_items(scope, todo_list)
      assert moved_first.id == second.id
      assert moved_second.id == first.id

      assert {:ok, _} = Todos.move_item(scope, second, :down)
      assert [moved_second, moved_first] = Todos.list_items(scope, todo_list)
      assert moved_second.id == second.id
      assert moved_first.id == first.id
    end

    test "broadcasts item changes on the list topic" do
      scope = household_scope_fixture()
      todo_list = todo_list_fixture(scope)
      Todos.subscribe_items(scope, todo_list)

      item = todo_item_fixture(scope, todo_list)
      assert_receive {:created, ^item}

      assert {:ok, item} = Todos.toggle_item(scope, item)
      assert_receive {:updated, ^item}
    end
  end
end
