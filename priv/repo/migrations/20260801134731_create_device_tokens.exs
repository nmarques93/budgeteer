defmodule Budgeteer.Repo.Migrations.CreateDeviceTokens do
  use Ecto.Migration

  def change do
    create table(:device_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :platform, :string, null: false, default: "ios"

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:device_tokens, [:user_id])
    create unique_index(:device_tokens, [:token])
  end
end
