defmodule Budgeteer.Repo do
  use Ecto.Repo,
    otp_app: :budgeteer,
    adapter: Ecto.Adapters.Postgres
end
