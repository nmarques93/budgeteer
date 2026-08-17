defmodule Budgeteer.Repo.Migrations.AddStatementReconciliationMetadata do
  use Ecto.Migration

  def change do
    alter table(:statements) do
      add :statement_period_start, :date
      add :statement_period_end, :date
      add :opening_balance_cents, :bigint
      add :closing_balance_cents, :bigint
    end
  end
end
