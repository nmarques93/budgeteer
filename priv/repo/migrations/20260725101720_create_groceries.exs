defmodule Budgeteer.Repo.Migrations.CreateGroceries do
  use Ecto.Migration

  def change do
    create table(:grocery_lists, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:grocery_lists, [:household_id])

    create table(:grocery_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :grocery_list_id, references(:grocery_lists, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :quantity, :decimal
      add :unit, :string
      add :checked, :boolean, null: false, default: false
      add :added_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :checked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:grocery_items, [:grocery_list_id])
  end
end
