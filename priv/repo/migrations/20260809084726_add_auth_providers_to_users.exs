defmodule Budgeteer.Repo.Migrations.AddAuthProvidersToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :auth_providers, {:array, :string}, null: false, default: ["email"]
    end
  end
end
