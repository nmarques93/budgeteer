defmodule Budgeteer.Todos.TodoItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "todo_items" do
    field :title, :string
    field :notes, :string
    field :due_date, :date
    field :completed, :boolean, default: false
    field :position, :integer, default: 0
    field :todo_list_id, :binary_id
    field :household_id, :binary_id
    field :created_by_id, :binary_id
    field :completed_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(todo_item, attrs, household_scope) do
    todo_item
    |> cast(attrs, [:title, :notes, :due_date])
    |> validate_required([:title])
    |> validate_length(:title, max: 240)
    |> put_change(:household_id, household_scope.user.household_id)
  end
end
