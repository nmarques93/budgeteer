defmodule Budgeteer.Repo.Migrations.AddTodoAssignmentsAndPriorities do
  use Ecto.Migration

  def change do
    alter table(:todo_items) do
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :priority, :string, null: false, default: "normal"
    end

    execute """
            ALTER TABLE todo_items
            ADD CONSTRAINT todo_items_assignee_household_fkey
            FOREIGN KEY (assignee_id, household_id)
            REFERENCES users (id, household_id)
            ON DELETE SET NULL (assignee_id)
            """,
            "ALTER TABLE todo_items DROP CONSTRAINT todo_items_assignee_household_fkey"
  end
end
