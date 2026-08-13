defmodule Budgeteer.Repo.Migrations.AddTodoRecurrence do
  use Ecto.Migration

  def change do
    alter table(:todo_items) do
      add :recurrence, :string, null: false, default: "none"
    end
  end
end
