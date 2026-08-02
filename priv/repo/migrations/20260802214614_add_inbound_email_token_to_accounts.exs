defmodule Budgeteer.Repo.Migrations.AddInboundEmailTokenToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :inbound_email_token, :string
    end

    create unique_index(:accounts, [:inbound_email_token])
  end
end
