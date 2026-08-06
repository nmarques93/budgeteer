defmodule Budgeteer.Repo.Migrations.AddIconToCategories do
  use Ecto.Migration

  def change do
    alter table(:categories) do
      add :icon, :string, null: false, default: "hero-tag"
    end
  end
end
