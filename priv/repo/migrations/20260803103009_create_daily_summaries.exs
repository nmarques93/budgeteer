defmodule Budgeteer.Repo.Migrations.CreateDailySummaries do
  use Ecto.Migration

  def change do
    create table(:daily_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :summary, :text, null: false, default: ""
      add :generated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:daily_summaries, [:household_id])
  end
end
