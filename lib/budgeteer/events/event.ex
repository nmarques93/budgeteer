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
    field :source, Ecto.Enum, values: [:local, :google], default: :local
    field :external_calendar_id, :string
    field :external_id, :string
    field :external_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs, household_scope) do
    event
    |> cast(attrs, [:title, :description, :date, :start_time, :end_time, :user_id])
    |> validate_required([:title, :date])
    |> validate_end_after_start()
    |> put_change(:household_id, household_scope.user.household_id)
    |> put_change(:source, :local)
  end

  def google_changeset(event, attrs, household_scope) do
    event
    |> cast(attrs, [
      :title,
      :description,
      :date,
      :start_time,
      :end_time,
      :user_id,
      :external_calendar_id,
      :external_id,
      :external_url
    ])
    |> validate_required([:title, :date, :external_calendar_id, :external_id])
    |> validate_end_after_start()
    |> put_change(:household_id, household_scope.user.household_id)
    |> put_change(:source, :google)
    |> put_change(:created_by_id, household_scope.user.id)
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
