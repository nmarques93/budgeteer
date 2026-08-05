defmodule Budgeteer.Insights.BudgetInsight do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "budget_insights" do
    field :insights, {:array, :string}, default: []
    field :generated_at, :utc_datetime
    field :locale, :string, default: "en"
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end
end
