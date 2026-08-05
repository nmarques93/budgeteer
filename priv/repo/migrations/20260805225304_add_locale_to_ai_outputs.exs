defmodule Budgeteer.Repo.Migrations.AddLocaleToAiOutputs do
  use Ecto.Migration

  def up do
    alter table(:budget_insights) do
      add :locale, :string, null: false, default: "en"
    end

    alter table(:daily_summaries) do
      add :locale, :string, null: false, default: "en"
    end

    drop unique_index(:budget_insights, [:household_id])
    drop unique_index(:daily_summaries, [:household_id])

    create unique_index(:budget_insights, [:household_id, :locale])
    create unique_index(:daily_summaries, [:household_id, :locale])
  end

  def down do
    drop unique_index(:budget_insights, [:household_id, :locale])
    drop unique_index(:daily_summaries, [:household_id, :locale])

    create unique_index(:budget_insights, [:household_id])
    create unique_index(:daily_summaries, [:household_id])

    alter table(:budget_insights) do
      remove :locale
    end

    alter table(:daily_summaries) do
      remove :locale
    end
  end
end
