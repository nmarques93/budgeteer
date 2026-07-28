defmodule Budgeteer.Repo.Migrations.AddHouseholdIdToGroceryItems do
  use Ecto.Migration

  def up do
    alter table(:grocery_items) do
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all)
    end

    execute """
    UPDATE grocery_items
    SET household_id = grocery_lists.household_id
    FROM grocery_lists
    WHERE grocery_lists.id = grocery_items.grocery_list_id
    """

    alter table(:grocery_items) do
      modify :household_id, :binary_id, null: false
    end

    create index(:grocery_items, [:household_id])
  end

  def down do
    alter table(:grocery_items) do
      remove :household_id
    end
  end
end
