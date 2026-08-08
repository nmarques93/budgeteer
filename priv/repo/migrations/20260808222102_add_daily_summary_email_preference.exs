defmodule Budgeteer.Repo.Migrations.AddDailySummaryEmailPreference do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :daily_summary_email_enabled, :boolean, null: false, default: false
    end
  end
end
