defmodule Budgeteer.Repo.Migrations.AddTodoReminderPreference do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :todo_reminders_enabled, :boolean, null: false, default: false
    end
  end
end
