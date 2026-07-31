defmodule Budgeteer.Repo.Migrations.CreateDismissedSubscriptions do
  use Ecto.Migration

  def change do
    create table(:dismissed_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :merchant_key, :string, null: false
      add :amount_cents, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:dismissed_subscriptions, [:household_id, :merchant_key, :amount_cents])
  end
end
