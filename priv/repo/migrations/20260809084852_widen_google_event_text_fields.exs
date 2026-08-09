defmodule Budgeteer.Repo.Migrations.WidenGoogleEventTextFields do
  use Ecto.Migration

  def change do
    alter table(:events) do
      modify :description, :text
      modify :external_url, :text
    end
  end
end
