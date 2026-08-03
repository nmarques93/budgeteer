defmodule Budgeteer.DailySummary.Summary do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "daily_summaries" do
    field :summary, :string, default: ""
    field :generated_at, :utc_datetime
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end
end
