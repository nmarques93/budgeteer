defmodule Budgeteer.Repo.Migrations.CreateMeals do
  use Ecto.Migration

  def change do
    create table(:recipes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :notes, :text
      add :ingredients, :map, null: false, default: fragment("'[]'::jsonb")

      timestamps(type: :utc_datetime)
    end

    create index(:recipes, [:household_id])

    create table(:planned_meals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :delete_all), null: false
      add :date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:planned_meals, [:household_id])
    create index(:planned_meals, [:date])
  end
end
