defmodule Budgeteer.Todos.TodoList do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "todo_lists" do
    field :name, :string
    field :archived_at, :utc_datetime
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(todo_list, attrs, household_scope) do
    todo_list
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
    |> put_change(:household_id, household_scope.user.household_id)
  end
end
