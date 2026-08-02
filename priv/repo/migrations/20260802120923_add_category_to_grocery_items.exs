defmodule Budgeteer.Repo.Migrations.AddCategoryToGroceryItems do
  use Ecto.Migration

  def change do
    alter table(:grocery_items) do
      add :category, :string
    end
  end
end
