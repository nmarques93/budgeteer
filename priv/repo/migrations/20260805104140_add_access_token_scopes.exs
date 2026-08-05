defmodule Budgeteer.Repo.Migrations.AddAccessTokenScopes do
  use Ecto.Migration

  def change do
    alter table(:access_tokens) do
      add :scopes, {:array, :string}, null: false, default: ["read"]
    end
  end
end
