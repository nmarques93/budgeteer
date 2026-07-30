defmodule Budgeteer.Repo.Migrations.AddBudgetAlertSentForToCategories do
  use Ecto.Migration

  def change do
    alter table(:categories) do
      add :budget_alert_sent_for, :date
    end
  end
end
