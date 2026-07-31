defmodule Budgeteer.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :title, :string, null: false
      add :description, :string
      add :date, :date, null: false
      add :start_time, :time
      add :end_time, :time

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:household_id, :date])
  end
end
