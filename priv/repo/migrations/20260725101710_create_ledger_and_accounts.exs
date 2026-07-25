defmodule Budgeteer.Repo.Migrations.CreateLedgerAndAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all), null: false
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :bank_name, :string
      add :currency, :string, null: false, default: "EUR"
      add :starting_balance_cents, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:accounts, [:household_id])

    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :color, :string
      add :budget_cents, :bigint
      add :type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:categories, [:household_id])
    create unique_index(:categories, [:household_id, :name])

    create table(:statements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :uploaded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :filename, :string, null: false
      add :storage_path, :string, null: false
      add :file_hash, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :raw_ai_output, :map
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:statements, [:account_id])
    create unique_index(:statements, [:account_id, :file_hash])

    create table(:transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :statement_id, references(:statements, type: :binary_id, on_delete: :nilify_all)
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
      add :added_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :date, :date, null: false
      add :amount_cents, :bigint, null: false
      add :merchant, :string
      add :description, :string
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:transactions, [:account_id])
    create index(:transactions, [:category_id])
    create index(:transactions, [:statement_id])
    create index(:transactions, [:date])
  end
end
