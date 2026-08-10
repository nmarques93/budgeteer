defmodule Budgeteer.Todos do
  @moduledoc """
  Household TODO lists and items. Lists are archived rather than deleted from
  the normal index, while item changes are broadcast on a topic scoped to the
  individual list.
  """

  import Ecto.Query, warn: false

  alias Budgeteer.Repo
  alias Budgeteer.Households
  alias Budgeteer.Households.Scope
  alias Budgeteer.Todos.{TodoItem, TodoList}

  ## Lists

  def subscribe_todo_lists(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{scope.user.household_id}:todo_lists")
  end

  defp broadcast_list(household_id, message) do
    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{household_id}:todo_lists", message)
  end

  def list_todo_lists(%Scope{} = scope, opts \\ []) do
    archived? = Keyword.get(opts, :archived, false)

    query =
      from l in TodoList,
        where: l.household_id == ^scope.user.household_id,
        order_by: [desc: l.inserted_at]

    query =
      if archived? do
        where(query, [l], not is_nil(l.archived_at))
      else
        where(query, [l], is_nil(l.archived_at))
      end

    Repo.all(query)
  end

  def get_todo_list!(%Scope{} = scope, id) do
    Repo.get_by!(TodoList, id: id, household_id: scope.user.household_id)
  end

  def create_todo_list(%Scope{} = scope, attrs) do
    with {:ok, todo_list = %TodoList{}} <-
           %TodoList{}
           |> TodoList.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_list(todo_list.household_id, {:created, todo_list})
      {:ok, todo_list}
    end
  end

  def update_todo_list(%Scope{} = scope, %TodoList{} = todo_list, attrs) do
    true = todo_list.household_id == scope.user.household_id

    with {:ok, todo_list = %TodoList{}} <-
           todo_list
           |> TodoList.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_list(todo_list.household_id, {:updated, todo_list})
      {:ok, todo_list}
    end
  end

  def archive_todo_list(%Scope{} = scope, %TodoList{} = todo_list),
    do: set_archived(scope, todo_list, DateTime.truncate(DateTime.utc_now(), :second))

  def unarchive_todo_list(%Scope{} = scope, %TodoList{} = todo_list),
    do: set_archived(scope, todo_list, nil)

  defp set_archived(%Scope{} = scope, %TodoList{} = todo_list, archived_at) do
    with :ok <- Households.require_owner(scope),
         true <- todo_list.household_id == scope.user.household_id,
         {:ok, todo_list = %TodoList{}} <-
           Repo.update(Ecto.Changeset.change(todo_list, archived_at: archived_at)) do
      broadcast_list(todo_list.household_id, {:updated, todo_list})
      {:ok, todo_list}
    else
      {:error, :forbidden} -> {:error, :forbidden}
    end
  end

  def delete_todo_list(%Scope{} = scope, %TodoList{} = todo_list) do
    case Households.require_owner(scope) do
      :ok ->
        true = todo_list.household_id == scope.user.household_id

        with {:ok, todo_list = %TodoList{}} <- Repo.delete(todo_list) do
          broadcast_list(todo_list.household_id, {:deleted, todo_list})
          {:ok, todo_list}
        end

      {:error, :forbidden} = error ->
        error
    end
  end

  def change_todo_list(%Scope{} = scope, %TodoList{} = todo_list, attrs \\ %{}) do
    TodoList.changeset(todo_list, attrs, scope)
  end

  ## Items

  def subscribe_items(%Scope{} = scope, %TodoList{} = todo_list) do
    true = todo_list.household_id == scope.user.household_id

    Phoenix.PubSub.subscribe(
      Budgeteer.PubSub,
      "household:#{scope.user.household_id}:todo_lists:#{todo_list.id}:items"
    )
  end

  defp broadcast_item(%TodoItem{} = item, message) do
    Phoenix.PubSub.broadcast(
      Budgeteer.PubSub,
      "household:#{item.household_id}:todo_lists:#{item.todo_list_id}:items",
      message
    )
  end

  def list_items(%Scope{} = scope, %TodoList{} = todo_list) do
    true = todo_list.household_id == scope.user.household_id

    Repo.all(
      from i in TodoItem,
        where: i.todo_list_id == ^todo_list.id and i.household_id == ^scope.user.household_id,
        order_by: [asc: i.completed, asc: i.position, asc: i.due_date, asc: i.inserted_at]
    )
  end

  def get_item!(%Scope{} = scope, id) do
    Repo.get_by!(TodoItem, id: id, household_id: scope.user.household_id)
  end

  def create_item(%Scope{} = scope, %TodoList{} = todo_list, attrs) do
    true = todo_list.household_id == scope.user.household_id
    position = next_position(scope, todo_list)

    changeset =
      %TodoItem{}
      |> TodoItem.changeset(attrs, scope)
      |> Ecto.Changeset.put_change(:todo_list_id, todo_list.id)
      |> Ecto.Changeset.put_change(:created_by_id, scope.user.id)
      |> Ecto.Changeset.put_change(:position, position)

    with {:ok, item = %TodoItem{}} <- Repo.insert(changeset) do
      broadcast_item(item, {:created, item})
      {:ok, item}
    end
  end

  def update_item(%Scope{} = scope, %TodoItem{} = item, attrs) do
    true = item.household_id == scope.user.household_id

    with {:ok, item = %TodoItem{}} <- Repo.update(TodoItem.changeset(item, attrs, scope)) do
      broadcast_item(item, {:updated, item})
      {:ok, item}
    end
  end

  def delete_item(%Scope{} = scope, %TodoItem{} = item) do
    true = item.household_id == scope.user.household_id

    with {:ok, item = %TodoItem{}} <- Repo.delete(item) do
      broadcast_item(item, {:deleted, item})
      {:ok, item}
    end
  end

  def toggle_item(%Scope{} = scope, %TodoItem{} = item) do
    true = item.household_id == scope.user.household_id

    attrs =
      if item.completed do
        %{completed: false, completed_by_id: nil}
      else
        %{completed: true, completed_by_id: scope.user.id}
      end

    with {:ok, item = %TodoItem{}} <- Repo.update(Ecto.Changeset.change(item, attrs)) do
      broadcast_item(item, {:updated, item})
      {:ok, item}
    end
  end

  def move_item(%Scope{} = scope, %TodoItem{} = item, direction) when direction in [:up, :down] do
    true = item.household_id == scope.user.household_id
    items = list_items(scope, %TodoList{id: item.todo_list_id, household_id: item.household_id})
    index = Enum.find_index(items, &(&1.id == item.id))
    target_index = if direction == :up, do: index - 1, else: index + 1

    case Enum.at(items, target_index) do
      nil -> {:ok, item}
      target -> swap_positions(item, target)
    end
  end

  def change_item(%Scope{} = scope, %TodoItem{} = item, attrs \\ %{}) do
    TodoItem.changeset(item, attrs, scope)
  end

  defp next_position(%Scope{} = scope, %TodoList{} = todo_list) do
    max_position =
      Repo.one(
        from i in TodoItem,
          where: i.todo_list_id == ^todo_list.id and i.household_id == ^scope.user.household_id,
          select: max(i.position)
      )

    (max_position || -1) + 1
  end

  defp swap_positions(%TodoItem{} = item, %TodoItem{} = target) do
    item_position = item.position
    target_position = target.position

    {:ok, {item, target}} =
      Repo.transaction(fn ->
        item = Repo.update!(Ecto.Changeset.change(item, position: target_position))
        target = Repo.update!(Ecto.Changeset.change(target, position: item_position))
        {item, target}
      end)

    broadcast_item(item, {:updated, item})
    broadcast_item(target, {:updated, target})
    {:ok, item}
  end
end
