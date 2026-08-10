defmodule Budgeteer.Repo.Migrations.CreateTodos do
  use Ecto.Migration

  def change do
    create table(:todo_lists, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:todo_lists, [:household_id])

    create unique_index(:todo_lists, [:id, :household_id],
             name: :todo_lists_id_household_id_index
           )

    create table(:todo_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :todo_list_id, references(:todo_lists, type: :binary_id, on_delete: :delete_all),
        null: false

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :notes, :text
      add :due_date, :date
      add :completed, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :completed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:todo_items, [:todo_list_id, :position])
    create index(:todo_items, [:household_id])

    execute """
            ALTER TABLE todo_items
            ADD CONSTRAINT todo_items_list_household_fkey
            FOREIGN KEY (todo_list_id, household_id)
            REFERENCES todo_lists (id, household_id)
            ON DELETE CASCADE
            """,
            "ALTER TABLE todo_items DROP CONSTRAINT todo_items_list_household_fkey"

    execute """
            ALTER TABLE todo_items
            ADD CONSTRAINT todo_items_created_by_household_fkey
            FOREIGN KEY (created_by_id, household_id)
            REFERENCES users (id, household_id)
            ON DELETE SET NULL (created_by_id)
            """,
            "ALTER TABLE todo_items DROP CONSTRAINT todo_items_created_by_household_fkey"

    execute """
            ALTER TABLE todo_items
            ADD CONSTRAINT todo_items_completed_by_household_fkey
            FOREIGN KEY (completed_by_id, household_id)
            REFERENCES users (id, household_id)
            ON DELETE SET NULL (completed_by_id)
            """,
            "ALTER TABLE todo_items DROP CONSTRAINT todo_items_completed_by_household_fkey"
  end
end
