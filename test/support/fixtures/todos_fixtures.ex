defmodule Budgeteer.TodosFixtures do
  def todo_list_fixture(scope, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "TODO list #{System.unique_integer()}"})
    {:ok, todo_list} = Budgeteer.Todos.create_todo_list(scope, attrs)
    todo_list
  end

  def todo_item_fixture(scope, todo_list, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{title: "Task #{System.unique_integer()}"})
    {:ok, item} = Budgeteer.Todos.create_item(scope, todo_list, attrs)
    item
  end
end
