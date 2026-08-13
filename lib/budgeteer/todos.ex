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
  alias Budgeteer.Households.User
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

  def subscribe_todo_items(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{scope.user.household_id}:todo_items")
  end

  defp broadcast_item(%TodoItem{} = item, message) do
    Phoenix.PubSub.broadcast(
      Budgeteer.PubSub,
      "household:#{item.household_id}:todo_lists:#{item.todo_list_id}:items",
      message
    )

    Phoenix.PubSub.broadcast(
      Budgeteer.PubSub,
      "household:#{item.household_id}:todo_items",
      message
    )
  end

  def list_items(%Scope{} = scope, %TodoList{} = todo_list) do
    true = todo_list.household_id == scope.user.household_id

    Repo.all(
      from i in TodoItem,
        where: i.todo_list_id == ^todo_list.id and i.household_id == ^scope.user.household_id,
        order_by: [asc: i.completed, asc: i.position, asc: i.due_date, asc: i.inserted_at],
        preload: :assignee
    )
  end

  def list_due_items(%Scope{} = scope, %Date{} = from, %Date{} = to) do
    Repo.all(
      from i in TodoItem,
        where:
          i.household_id == ^scope.user.household_id and
            i.due_date >= ^from and i.due_date <= ^to and i.completed == false,
        order_by: [asc: i.due_date, asc: i.position],
        preload: :assignee
    )
  end

  def get_item!(%Scope{} = scope, id) do
    TodoItem
    |> Repo.get_by!(id: id, household_id: scope.user.household_id)
    |> Repo.preload(:assignee)
  end

  def create_item(%Scope{} = scope, %TodoList{} = todo_list, attrs) do
    true = todo_list.household_id == scope.user.household_id
    position = next_position(scope, todo_list)

    changeset =
      %TodoItem{}
      |> TodoItem.changeset(attrs, scope)
      |> validate_assignee_scope(scope)
      |> Ecto.Changeset.put_change(:todo_list_id, todo_list.id)
      |> Ecto.Changeset.put_change(:created_by_id, scope.user.id)
      |> Ecto.Changeset.put_change(:position, position)

    with {:ok, item = %TodoItem{}} <- Repo.insert(changeset) do
      item = preload_item(item)
      broadcast_item(item, {:created, item})
      {:ok, item}
    end
  end

  def update_item(%Scope{} = scope, %TodoItem{} = item, attrs) do
    true = item.household_id == scope.user.household_id

    changeset = TodoItem.changeset(item, attrs, scope) |> validate_assignee_scope(scope)

    with {:ok, item = %TodoItem{}} <- Repo.update(changeset) do
      item = preload_item(item)
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

    with {:ok, {item, next_item}} <-
           Repo.transaction(fn ->
             item = Repo.update!(Ecto.Changeset.change(item, attrs))
             next_item = if item.completed, do: create_next_recurring(scope, item), else: nil
             {item, next_item}
           end) do
      item = preload_item(item)
      broadcast_item(item, {:updated, item})

      if next_item do
        broadcast_item(preload_item(next_item), {:created, preload_item(next_item)})
      end

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

  defp create_next_recurring(%Scope{} = scope, %TodoItem{due_date: due_date} = item)
       when not is_nil(due_date) and item.recurrence != :none do
    attrs = %{
      title: item.title,
      notes: item.notes,
      due_date: next_due_date(due_date, item.recurrence),
      priority: item.priority,
      recurrence: item.recurrence,
      assignee_id: item.assignee_id
    }

    %TodoItem{}
    |> TodoItem.changeset(attrs, scope)
    |> Ecto.Changeset.put_change(:todo_list_id, item.todo_list_id)
    |> Ecto.Changeset.put_change(:created_by_id, scope.user.id)
    |> Ecto.Changeset.put_change(
      :position,
      next_position(scope, %TodoList{id: item.todo_list_id, household_id: item.household_id})
    )
    |> validate_assignee_scope(scope)
    |> Repo.insert!()
  end

  defp create_next_recurring(_scope, _item), do: nil

  defp next_due_date(date, recurrence) do
    next_date =
      case recurrence do
        :daily -> Date.add(date, 1)
        :weekly -> Date.add(date, 7)
        :monthly -> next_month_date(date)
      end

    if Date.compare(next_date, Date.utc_today()) == :lt,
      do: next_due_date(next_date, recurrence),
      else: next_date
  end

  defp next_month_date(date) do
    next_month = date |> Date.beginning_of_month() |> Date.add(32) |> Date.beginning_of_month()
    day = min(date.day, Date.days_in_month(next_month))
    Date.add(next_month, day - 1)
  end

  defp validate_assignee_scope(changeset, %Scope{} = scope) do
    case Ecto.Changeset.get_field(changeset, :assignee_id) do
      nil ->
        changeset

      assignee_id ->
        query =
          from u in User,
            where: u.id == ^assignee_id and u.household_id == ^scope.user.household_id

        if Repo.exists?(query),
          do: changeset,
          else:
            Ecto.Changeset.add_error(changeset, :assignee_id, "does not belong to this household")
    end
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

    item = preload_item(item)
    target = preload_item(target)
    broadcast_item(item, {:updated, item})
    broadcast_item(target, {:updated, target})
    {:ok, item}
  end

  defp preload_item(item), do: Repo.preload(item, :assignee)
end
