defmodule Budgeteer.Repo.Migrations.AddGoogleCalendarFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_calendar, :binary
    end

    alter table(:events) do
      add :source, :string, null: false, default: "local"
      add :external_calendar_id, :string
      add :external_id, :string
      add :external_url, :string
    end

    create unique_index(:events, [:source, :user_id, :external_calendar_id, :external_id],
             name: :events_google_external_identity_index,
             where: "source = 'google' AND external_id IS NOT NULL"
           )
  end
end
