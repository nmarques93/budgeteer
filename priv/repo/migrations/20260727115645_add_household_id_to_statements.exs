defmodule Budgeteer.Repo.Migrations.AddHouseholdIdToStatements do
  use Ecto.Migration

  def up do
    alter table(:statements) do
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all)
    end

    execute """
    UPDATE statements
    SET household_id = accounts.household_id
    FROM accounts
    WHERE accounts.id = statements.account_id
    """

    alter table(:statements) do
      modify :household_id, :binary_id, null: false
    end

    create index(:statements, [:household_id])
  end

  def down do
    alter table(:statements) do
      remove :household_id
    end
  end
end
