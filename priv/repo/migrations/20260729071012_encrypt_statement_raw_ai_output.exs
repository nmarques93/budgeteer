defmodule Budgeteer.Repo.Migrations.EncryptStatementRawAiOutput do
  use Ecto.Migration

  # jsonb -> bytea has no implicit cast, so a plain `modify` can't do this.
  # Confirmed no production data exists yet (every row's raw_ai_output was
  # NULL at the time this was written) — `USING NULL` is intentional, not
  # an oversight. If this ever runs against a database with real processed
  # statements, back up `raw_ai_output` first; this migration discards it.
  def up do
    execute "ALTER TABLE statements ALTER COLUMN raw_ai_output TYPE bytea USING NULL"
  end

  def down do
    execute "ALTER TABLE statements ALTER COLUMN raw_ai_output TYPE jsonb USING NULL"
  end
end
