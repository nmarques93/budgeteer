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
    field :priority, Ecto.Enum, values: [:low, :normal, :high], default: :normal
    field :recurrence, Ecto.Enum, values: [:none, :daily, :weekly, :monthly], default: :none
    field :assignee_id, :binary_id
    field :todo_list_id, :binary_id
    field :household_id, :binary_id
    field :created_by_id, :binary_id
    field :completed_by_id, :binary_id

    belongs_to :assignee, Budgeteer.Households.User,
      foreign_key: :assignee_id,
      define_field: false

    timestamps(type: :utc_datetime)
  end

  def changeset(todo_item, attrs, household_scope) do
    todo_item
    |> cast(attrs, [:title, :notes, :due_date, :priority, :assignee_id, :recurrence])
    |> validate_required([:title])
    |> validate_length(:title, max: 240)
    |> validate_inclusion(:priority, [:low, :normal, :high])
    |> validate_inclusion(:recurrence, [:none, :daily, :weekly, :monthly])
    |> validate_recurrence_due_date()
    |> put_change(:household_id, household_scope.user.household_id)
  end

  defp validate_recurrence_due_date(changeset) do
    if get_field(changeset, :recurrence) != :none and is_nil(get_field(changeset, :due_date)) do
      add_error(changeset, :due_date, "is required for recurring tasks")
    else
      changeset
    end
  end
end
