defmodule Budgeteer.Repo.Migrations.AddImagePathToRecipes do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      add :image_path, :string
    end
  end
end
