defmodule Budgeteer.Repo.Migrations.AddHouseholdIdToTransactions do
  use Ecto.Migration

  def up do
    alter table(:transactions) do
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all)
    end

    execute """
    UPDATE transactions
    SET household_id = accounts.household_id
    FROM accounts
    WHERE accounts.id = transactions.account_id
    """

    alter table(:transactions) do
      modify :household_id, :binary_id, null: false
    end

    create index(:transactions, [:household_id])
  end

  def down do
    alter table(:transactions) do
      remove :household_id
    end
  end
end
