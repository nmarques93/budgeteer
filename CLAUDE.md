# Budgeteer — Claude Code Context

## What This App Is

**Budgeteer** is a family budgeting PWA. It reads bank statements via Claude (PDF/image → structured transactions), syncs in real time across household members via Phoenix PubSub, and includes a shared grocery list.

See `PLAN.md` for the original build plan this project was scaffolded from.

---

## Stack

| Layer | Choice |
|---|---|
| Backend + Frontend | Elixir + Phoenix + LiveView (PWA, no separate JS framework) |
| Database | PostgreSQL |
| Background jobs | Oban (`statements` queue, for statement-parsing jobs) |
| AI | Anthropic Claude API via `Req` — statement parsing |
| Auth | `mix phx.gen.auth`, generated under the `Households` context (see below) |
| File storage | Local disk in `priv/statements` for now — see Decisions |

---

## Decisions Made During Scaffolding

These deviate from or sharpen the original `PLAN.md` and should be treated as settled unless revisited explicitly:

- **Auth context is named `Households`, not `Accounts`.** `mix phx.gen.auth` defaults to an `Accounts` context, which would collide with the planned bank-`accounts` context (`Budgeteer.Accounts` for `Account`/bank-account records). Ran as `mix phx.gen.auth Households User users`, so `Budgeteer.Households` owns `User`, `UserToken`, `UserNotifier`, and the `Scope` struct (Phoenix 1.8's per-request scoping pattern) — as well as `Household` itself.
- **All primary keys are UUIDs** (`binary_id`), matching the Perks project's convention. Project was regenerated with `mix phx.new --binary-id` for this — check `config/config.exs` (`generators: [binary_id: true]`) if a generator ever produces integer IDs unexpectedly.
- **Account balance is computed, not stored.** The plan's `accounts.balance_cents` (manually maintained) was replaced with `accounts.starting_balance_cents`; current balance = `starting_balance_cents + sum(transactions.amount_cents)`. Avoids drift between a manually-edited field and the actual ledger. Implement this as a query/function in `Budgeteer.Ledger`, not a stored column.
- **Money is stored as cents but never *typed* as cents.** Every `*_cents` field (`accounts.starting_balance_cents`, `transactions.amount_cents`, `categories.budget_cents`) has a matching virtual string field on its schema (`starting_balance`, `amount`, `budget`) that the LiveView forms actually bind to — the user types `"1500.00"`, never `150000`. `lib/budgeteer/money.ex` (`Budgeteer.Money`) is the one place that boundary gets crossed: `to_cents/1` parses the decimal string (via `Decimal`, not floats — see the `Repo.aggregate` gotcha below for why), `to_decimal_string/1` goes the other way for prefilling edit forms, and `format/1` renders a signed euro string (`"-€42.50"`) for display. Each schema's changeset has a small `put_x_cents/1` private step that converts the virtual field into the real one and adds a changeset error if parsing fails. Follow this exact pattern for any new money field (e.g. a future `PriceOrRateRecord.price_cents`) — never expose a raw `_cents` input in a form.
- **EUR-only logic for now, `currency` field kept on `accounts`.** No multi-currency conversion or display logic should be built yet — treat every amount as EUR — but don't remove the column, since the user wants the door open for it later.
- **Local disk storage for statement uploads**, not S3. Path is `config :budgeteer, :statement_storage_path` (defaults to `priv/statements`). Revisit S3 (`ex_aws`/`ex_aws_s3` — not currently a dependency) only when actually deploying.
- **One household per user.** `users.household_id` is a nullable FK (nullable at the DB level only because a user can theoretically exist before being assigned to a household during onboarding) — application logic should treat it as required once registration/invite flow is built. Do not model multi-household membership.
- **Registration creates a household.** The registration form asks for a household name; `Households.register_user/1` creates the `Household` and `User` (as `:owner`) in one transaction — see `lib/budgeteer/households/user.ex` (`registration_changeset/3`) and `lib/budgeteer/households.ex`. Joining an existing household via an invite link is separate, not-yet-built work.
- **Standard Phoenix asset pipeline was added post-scaffold.** `mix phx.new --no-assets` (per `PLAN.md`'s original suggestion of "Tailwind via CDN") leaves `app.js` as an inert placeholder with *no LiveView JS client at all* — forms silently fall back to plain HTML POSTs with no matching controller route. Since this app is LiveView-first, that's not viable even for local dev, so the standard `esbuild` + `tailwind` + `daisyui`/`heroicons` setup (matching a non-`--no-assets` `mix phx.new`) was wired in instead: `assets/` directory, `config :esbuild`/`config :tailwind` in `config.exs`, `watchers` in `dev.exs`, and `assets.setup`/`assets.build`/`assets.deploy` mix aliases. Run `mix assets.setup && mix assets.build` after a fresh clone (or just `mix setup`).
- **Duplicate statement protection**: `statements` has a `file_hash` column with a unique index on `(account_id, file_hash)`, not in the original plan. Compute a SHA-256 of the uploaded file before insert to prevent double-importing the same statement.
- **Household-scoped generators.** `config :budgeteer, :scopes` (`config/config.exs`) defines a `household` scope (`access_path: [:user, :household_id]`, `schema_key: :household_id`) as the **default** — `mix phx.gen.live`/`phx.gen.context` etc. will automatically thread a `scope` param through every generated context function (`list_x(scope)`, `get_x!(scope, id)`, ...), scope queries by `household_id`, assert ownership on update/delete, and set up per-household PubSub broadcasting (`"household:#{household_id}:resource"`) for free. Use this for every remaining Phase 1 resource (`statements`, `grocery_lists`/`grocery_items`) rather than hand-rolling scoping — just run the generator, then **delete the generated migration** (tables already exist from the initial scaffolding migrations) and wire up routes/nav manually. A `user` scope (by `user_id`) also exists but is not default — pass `--scope user` explicitly if a future resource is genuinely per-user rather than per-household. Test fixtures: `household_scope_fixture/0,1` in `test/support/fixtures/households_fixtures.ex` (added alongside the pre-existing `user_scope_fixture/0,1` — both just wrap `Scope.for_user/1`, since our `Scope` struct doesn't distinguish scope "kind").
  - **Gotcha for child tables scoped transitively through a parent FK** (like `transactions` through `account_id → accounts.household_id`): the scope mechanism assumes the table has its *own* `household_id` column and will fail loudly (`undefined_column`) if it doesn't. The original schema deliberately didn't put `household_id` directly on `transactions`/`statements` (avoid redundancy — household is reachable via `account_id`). We chose to **add a denormalized `household_id` column via migration anyway** (see `20260726125502_add_household_id_to_transactions.exs`) rather than hand-write scoping for these tables — keeps every resource on the same generator recipe, and makes household-filtered queries not need a join. `statements` will need the identical treatment when that resource gets built.
  - **Gotcha for a second required FK the scope doesn't know about** (like `transactions.account_id`): the generator casts/requires it as a normal field, but nothing sets it automatically the way `household_id` gets set via the scope — the form doesn't (and shouldn't) expose an `account_id` input, so it must be injected server-side. Pattern used in `lib/budgeteer_web/live/transaction_live/form.ex`: `apply_action(:new, ...)` pre-populates the placeholder struct's `account_id` (fine for the live-validate path, which reads off the existing struct), **and** `save_transaction(socket, :new, params)` explicitly does `Map.put(params, "account_id", account.id)` before calling `create_transaction/2` — because `create_transaction` builds a *fresh* `%Transaction{}` from just the submitted params, not from the assigned placeholder, so anything not in the form (and not scope-injected) silently comes back nil and fails `validate_required`.
  - **`Repo.aggregate(query, :sum, :field)` returns a `Decimal`, not a plain integer/float**, even for a `bigint` column — Postgres's `sum()` returns `numeric`. Adding a `Decimal` to a plain integer raises `ArithmeticError`. Always `Decimal.to_integer/1` (or `Decimal.add/2`) before mixing with plain arithmetic — see `Ledger.current_balance_cents/1`.
  - **Virtual fields break generated tests that compare whole structs with `==`.** Once a schema has a virtual field (e.g. `starting_balance`, `amount`, `budget` — see the money-input decision above), the struct returned by `create_x`/`update_x` (virtual field populated from the just-submitted params) will never `==` the same row freshly fetched from the DB (virtual field is `nil`, since it isn't persisted). Fix at the test level, not the schema level: strip the virtual field before comparing, e.g. `account = %{account_fixture(scope) | starting_balance: nil}`. Search `ledger_test.exs` for this pattern before assuming a struct-equality test failure means real broken behavior.
  - **Generated fixtures reuse a static default name** (`"some name"`), which collides with any real `unique_index` the moment a test both seeds a fixture *and* creates another record with the same generator-default name in the same household (this happened with `categories`, which already had `unique_index(:household_id, :name)` from the very first migration — the generated `phx.gen.live` test's own `setup` fixture collided with its own `@create_attrs`). Give fixtures for uniquely-constrained fields a unique default (e.g. `"some name #{System.unique_integer()}"`) rather than assuming the generator got it right.
- **`raw_ai_output`** is stored as a plain `jsonb` map, unencrypted — same tradeoff as the original plan. It contains merchant names, amounts, and dates from bank statements. Fine for local dev; revisit before any real deployment (this is a bank statement DB, all money data deserves encryption-at-rest scrutiny before going live — this isn't done yet).

---

## Data Model (as migrated)

```
households
  id (uuid), name
  inserted_at / updated_at

users                              # Budgeteer.Households.User
  id (uuid), household_id (uuid FK, nullable), email, hashed_password
  name, role (string, default "owner"), confirmed_at
  -- phx_gen_auth fields (users_tokens table also exists)

accounts                           # Budgeteer.Ledger (planned) — bank accounts
  id (uuid), household_id (uuid FK), owner_id (uuid FK, nullable)
  name, bank_name, currency (default "EUR")
  starting_balance_cents (bigint)  -- current balance is computed, see Decisions

categories
  id (uuid), household_id (uuid FK)
  name, color, budget_cents (nullable), type (income | expense)
  unique on (household_id, name)

statements
  id (uuid), account_id (uuid FK), uploaded_by_id (uuid FK, nullable)
  filename, storage_path, file_hash (unique per account_id)
  status (pending | processing | processed | failed)
  raw_ai_output (jsonb), error_message

transactions
  id (uuid), account_id (uuid FK), statement_id (uuid FK, nullable)
  category_id (uuid FK, nullable), added_by_id (uuid FK, nullable)
  date, amount_cents (bigint, negative = debit), merchant, description, notes

grocery_lists
  id (uuid), household_id (uuid FK), name, archived_at (nullable)

grocery_items
  id (uuid), grocery_list_id (uuid FK), name, quantity, unit
  checked (boolean), added_by_id (uuid FK, nullable), checked_by_id (uuid FK, nullable)
```

`Household` and `User` (with `household_id`/`role`/`name` fields) are built out as Ecto schemas in `Budgeteer.Households`, including registration. `Account`, `Transaction`, and `Category` are built out in `Budgeteer.Ledger` (`lib/budgeteer/ledger.ex`, `lib/budgeteer/ledger/{account,transaction,category}.ex`) with full LiveView CRUD — accounts at `/accounts`, categories at `/categories`, transactions nested at `/accounts/:account_id/transactions` (a transaction always belongs to one specific account, so its LiveViews aren't flat like Account's/Category's) and optionally tagged with a category via `transactions.category_id`. `Ledger.current_balance_cents/1` computes each account's live balance from `starting_balance_cents` + the sum of its transactions. Note: `transactions.household_id` was added via migration after the fact — see the scoping gotcha above. Schemas/contexts for `statements`, `grocery_lists`, `grocery_items` are still just migrations — not yet built.

---

## Project Conventions

- Money as `bigint` cents everywhere — never floats.
- Context modules follow Phoenix conventions: `Budgeteer.Households`, `Budgeteer.Ledger` (accounts/categories/transactions), `Budgeteer.Statements`, `Budgeteer.AI`, `Budgeteer.Groceries`.
- Broadcast household-scoped writes via `Phoenix.PubSub` on topic `"household:#{household_id}"`, subscribed to in `mount/3` of relevant LiveViews.
- Oban jobs live under `Budgeteer.Statements` (e.g. `Budgeteer.Statements.ParseWorker`), queue `:statements`.
- Tests: ExUnit (as generated); no Mox/Faker installed yet — add if/when the Anthropic client or seed data needs them.

---

## Local Dev Setup

```bash
brew services start postgresql@17   # if not already running
cd budgeteer
mix ecto.create && mix ecto.migrate
mix phx.server
```

A local Postgres role `postgres`/`postgres` (superuser) was created on this machine to match Phoenix's default dev config — the Homebrew `postgresql@17` install otherwise only has a `nmarques` peer-auth role.

**Environment note:** this machine's `postgresql@17` Homebrew install was missing its contrib extensions (`citext`, `pg_trgm`, `uuid-ossp`, etc.) from the active `pkglibdir` — only PostGIS symlinks (from the Perks project) were present. Fixed by symlinking the full contrib set from the Homebrew Cellar into `/opt/homebrew/lib/postgresql@17/`. This was a pre-existing local environment issue, not specific to this project, and also unblocks Perks if it hits the same thing.

---

## Build Phases (from PLAN.md, unchanged)

1. Core ledger — auth ✅, registration creates a household ✅, account CRUD ✅, manual transaction entry ✅, category CRUD ✅ — invite-to-join flow, dashboard **not yet built**
2. AI statement import (Oban + Claude)
3. Real-time sync (PubSub + Presence)
4. Grocery list
5. PWA polish (manifest, service worker)
