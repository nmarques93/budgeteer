defmodule Budgeteer.Repo.Migrations.AddHouseholdIntegrityConstraints do
  use Ecto.Migration

  def change do
    execute "CREATE UNIQUE INDEX accounts_id_household_id_index ON accounts (id, household_id)",
      "DROP INDEX accounts_id_household_id_index"

    execute "CREATE UNIQUE INDEX categories_id_household_id_index ON categories (id, household_id)",
      "DROP INDEX categories_id_household_id_index"

    execute "CREATE UNIQUE INDEX users_id_household_id_index ON users (id, household_id)",
      "DROP INDEX users_id_household_id_index"

    execute "CREATE UNIQUE INDEX grocery_lists_id_household_id_index ON grocery_lists (id, household_id)",
      "DROP INDEX grocery_lists_id_household_id_index"

    execute "CREATE UNIQUE INDEX recipes_id_household_id_index ON recipes (id, household_id)",
      "DROP INDEX recipes_id_household_id_index"

    execute """
    ALTER TABLE transactions
    ADD CONSTRAINT transactions_account_household_fkey
    FOREIGN KEY (account_id, household_id)
    REFERENCES accounts (id, household_id)
    ON DELETE CASCADE
    """, "ALTER TABLE transactions DROP CONSTRAINT transactions_account_household_fkey"

    execute """
    ALTER TABLE transactions
    ADD CONSTRAINT transactions_category_household_fkey
    FOREIGN KEY (category_id, household_id)
    REFERENCES categories (id, household_id)
    ON DELETE SET NULL (category_id)
    """, "ALTER TABLE transactions DROP CONSTRAINT transactions_category_household_fkey"

    execute """
    ALTER TABLE transactions
    ADD CONSTRAINT transactions_added_by_household_fkey
    FOREIGN KEY (added_by_id, household_id)
    REFERENCES users (id, household_id)
    ON DELETE SET NULL (added_by_id)
    """, "ALTER TABLE transactions DROP CONSTRAINT transactions_added_by_household_fkey"

    execute """
    ALTER TABLE statements
    ADD CONSTRAINT statements_account_household_fkey
    FOREIGN KEY (account_id, household_id)
    REFERENCES accounts (id, household_id)
    ON DELETE CASCADE
    """, "ALTER TABLE statements DROP CONSTRAINT statements_account_household_fkey"

    execute """
    ALTER TABLE statements
    ADD CONSTRAINT statements_uploaded_by_household_fkey
    FOREIGN KEY (uploaded_by_id, household_id)
    REFERENCES users (id, household_id)
    ON DELETE SET NULL (uploaded_by_id)
    """, "ALTER TABLE statements DROP CONSTRAINT statements_uploaded_by_household_fkey"

    execute """
    ALTER TABLE grocery_items
    ADD CONSTRAINT grocery_items_list_household_fkey
    FOREIGN KEY (grocery_list_id, household_id)
    REFERENCES grocery_lists (id, household_id)
    ON DELETE CASCADE
    """, "ALTER TABLE grocery_items DROP CONSTRAINT grocery_items_list_household_fkey"

    execute """
    ALTER TABLE grocery_items
    ADD CONSTRAINT grocery_items_added_by_household_fkey
    FOREIGN KEY (added_by_id, household_id)
    REFERENCES users (id, household_id)
    ON DELETE SET NULL (added_by_id)
    """, "ALTER TABLE grocery_items DROP CONSTRAINT grocery_items_added_by_household_fkey"

    execute """
    ALTER TABLE grocery_items
    ADD CONSTRAINT grocery_items_checked_by_household_fkey
    FOREIGN KEY (checked_by_id, household_id)
    REFERENCES users (id, household_id)
    ON DELETE SET NULL (checked_by_id)
    """, "ALTER TABLE grocery_items DROP CONSTRAINT grocery_items_checked_by_household_fkey"

    execute """
    ALTER TABLE planned_meals
    ADD CONSTRAINT planned_meals_recipe_household_fkey
    FOREIGN KEY (recipe_id, household_id)
    REFERENCES recipes (id, household_id)
    ON DELETE CASCADE
    """, "ALTER TABLE planned_meals DROP CONSTRAINT planned_meals_recipe_household_fkey"

    execute """
    ALTER TABLE events
    ADD CONSTRAINT events_user_household_fkey
    FOREIGN KEY (user_id, household_id)
    REFERENCES users (id, household_id)
    ON DELETE SET NULL (user_id)
    """, "ALTER TABLE events DROP CONSTRAINT events_user_household_fkey"

    execute """
    ALTER TABLE events
    ADD CONSTRAINT events_created_by_household_fkey
    FOREIGN KEY (created_by_id, household_id)
    REFERENCES users (id, household_id)
    ON DELETE SET NULL (created_by_id)
    """, "ALTER TABLE events DROP CONSTRAINT events_created_by_household_fkey"
  end
end
