defmodule Budgeteer.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "events" do
    field :title, :string
    field :description, :string
    field :date, :date
    field :start_time, :time
    field :end_time, :time
    field :household_id, :binary_id
    field :user_id, :binary_id
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs, household_scope) do
    event
    |> cast(attrs, [:title, :description, :date, :start_time, :end_time, :user_id])
    |> validate_required([:title, :date])
    |> validate_end_after_start()
    |> put_change(:household_id, household_scope.user.household_id)
  end

  defp validate_end_after_start(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && Time.compare(end_time, start_time) != :gt do
      add_error(changeset, :end_time, "must be after the start time")
    else
      changeset
    end
  end
end
