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
- **`/dashboard` is the post-login landing page**, not `/users/settings` (the `phx.gen.auth` default). `BudgeteerWeb.UserAuth.signed_in_path/1` was changed accordingly. It shows total balance across all accounts, this-month totals per category (only for categorized transactions — `Ledger.monthly_category_totals/2`, inner-joined against `categories`, against `budget_cents` if set), and the household's most recent transactions across every account (`Ledger.list_recent_transactions/2`). Read-only — no forms — but still subscribes to all three PubSub topics (accounts/transactions/categories) and reloads on any change, same convention as every other LiveView.
- **Standard Phoenix asset pipeline was added post-scaffold.** `mix phx.new --no-assets` (per `PLAN.md`'s original suggestion of "Tailwind via CDN") leaves `app.js` as an inert placeholder with *no LiveView JS client at all* — forms silently fall back to plain HTML POSTs with no matching controller route. Since this app is LiveView-first, that's not viable even for local dev, so the standard `esbuild` + `tailwind` + `daisyui`/`heroicons` setup (matching a non-`--no-assets` `mix phx.new`) was wired in instead: `assets/` directory, `config :esbuild`/`config :tailwind` in `config.exs`, `watchers` in `dev.exs`, and `assets.setup`/`assets.build`/`assets.deploy` mix aliases. Run `mix assets.setup && mix assets.build` after a fresh clone (or just `mix setup`).
- **Duplicate statement protection**: `statements` has a `file_hash` column with a unique index on `(account_id, file_hash)`, not in the original plan. Compute a SHA-256 of the uploaded file before insert to prevent double-importing the same statement.
- **Household-scoped generators.** `config :budgeteer, :scopes` (`config/config.exs`) defines a `household` scope (`access_path: [:user, :household_id]`, `schema_key: :household_id`) as the **default** — `mix phx.gen.live`/`phx.gen.context` etc. will automatically thread a `scope` param through every generated context function (`list_x(scope)`, `get_x!(scope, id)`, ...), scope queries by `household_id`, assert ownership on update/delete, and set up per-household PubSub broadcasting (`"household:#{household_id}:resource"`) for free. Use this for every remaining Phase 1 resource (`statements`, `grocery_lists`/`grocery_items`) rather than hand-rolling scoping — just run the generator, then **delete the generated migration** (tables already exist from the initial scaffolding migrations) and wire up routes/nav manually. A `user` scope (by `user_id`) also exists but is not default — pass `--scope user` explicitly if a future resource is genuinely per-user rather than per-household. Test fixtures: `household_scope_fixture/0,1` in `test/support/fixtures/households_fixtures.ex` (added alongside the pre-existing `user_scope_fixture/0,1` — both just wrap `Scope.for_user/1`, since our `Scope` struct doesn't distinguish scope "kind").
  - **Gotcha for child tables scoped transitively through a parent FK** (like `transactions` through `account_id → accounts.household_id`): the scope mechanism assumes the table has its *own* `household_id` column and will fail loudly (`undefined_column`) if it doesn't. The original schema deliberately didn't put `household_id` directly on `transactions`/`statements` (avoid redundancy — household is reachable via `account_id`). We chose to **add a denormalized `household_id` column via migration anyway** (see `20260726125502_add_household_id_to_transactions.exs`) rather than hand-write scoping for these tables — keeps every resource on the same generator recipe, and makes household-filtered queries not need a join. `statements` will need the identical treatment when that resource gets built.
  - **Gotcha for a second required FK the scope doesn't know about** (like `transactions.account_id`): the generator casts/requires it as a normal field, but nothing sets it automatically the way `household_id` gets set via the scope — the form doesn't (and shouldn't) expose an `account_id` input, so it must be injected server-side. Pattern used in `lib/budgeteer_web/live/transaction_live/form.ex`: `apply_action(:new, ...)` pre-populates the placeholder struct's `account_id` (fine for the live-validate path, which reads off the existing struct), **and** `save_transaction(socket, :new, params)` explicitly does `Map.put(params, "account_id", account.id)` before calling `create_transaction/2` — because `create_transaction` builds a *fresh* `%Transaction{}` from just the submitted params, not from the assigned placeholder, so anything not in the form (and not scope-injected) silently comes back nil and fails `validate_required`.
  - **`Repo.aggregate(query, :sum, :field)` returns a `Decimal`, not a plain integer/float**, even for a `bigint` column — Postgres's `sum()` returns `numeric`. Adding a `Decimal` to a plain integer raises `ArithmeticError`. Always `Decimal.to_integer/1` (or `Decimal.add/2`) before mixing with plain arithmetic — see `Ledger.current_balance_cents/1`.
  - **Virtual fields break generated tests that compare whole structs with `==`.** Once a schema has a virtual field (e.g. `starting_balance`, `amount`, `budget` — see the money-input decision above), the struct returned by `create_x`/`update_x` (virtual field populated from the just-submitted params) will never `==` the same row freshly fetched from the DB (virtual field is `nil`, since it isn't persisted). Fix at the test level, not the schema level: strip the virtual field before comparing, e.g. `account = %{account_fixture(scope) | starting_balance: nil}`. Search `ledger_test.exs` for this pattern before assuming a struct-equality test failure means real broken behavior.
  - **Generated fixtures reuse a static default name** (`"some name"`), which collides with any real `unique_index` the moment a test both seeds a fixture *and* creates another record with the same generator-default name in the same household (this happened with `categories`, which already had `unique_index(:household_id, :name)` from the very first migration — the generated `phx.gen.live` test's own `setup` fixture collided with its own `@create_attrs`). Give fixtures for uniquely-constrained fields a unique default (e.g. `"some name #{System.unique_integer()}"`) rather than assuming the generator got it right.
- **`raw_ai_output`** is stored as a plain `jsonb` map, unencrypted — same tradeoff as the original plan. It contains merchant names, amounts, and dates from bank statements. Fine for local dev; revisit before any real deployment (this is a bank statement DB, all money data deserves encryption-at-rest scrutiny before going live — this isn't done yet).
- **The Oban worker never creates `Transaction` records.** `Budgeteer.Statements.ParseWorker` only calls the AI client and writes `raw_ai_output` + `status` (`pending → processing → processed | failed`) on the `Statement`. Real `Transaction` rows only get created when the user reviews and confirms extracted rows on `StatementLive.Review` — a bad AI parse can never silently pollute the ledger. `Ledger.Transaction` gained a `statement_id` field (cast, not form-exposed — same "cast but not exposed" precedent as `account_id`) so review-confirmed transactions can be traced back to their source statement.
- **`Budgeteer.Statements` was hand-written, not `mix phx.gen.live`'d**, unlike every other Phase 1 resource — the household-scope generator recipe (see below) assumes a simple user-editable form, and `statements`' fields (`storage_path`, `file_hash`, `status`, `raw_ai_output`) are all system-set, never user input. It follows the exact same shape as `Ledger` by hand (subscribe/broadcast per household on `"household:#{id}:statements"`, scoped `list_x`/`get_x!`/`delete_x`), plus an **unscoped** `get_statement!/1` (arity 1) for the Oban worker, which runs outside a request/user context. `Statement.status_changeset/2` is a separate, unvalidated changeset for the worker's own `status`/`raw_ai_output`/`error_message` writes — no form ceremony needed since it's never fed user input. `statements` got the identical `household_id`-backfill-migration treatment as `transactions` (see the gotcha above) — see `20260727115645_add_household_id_to_statements.exs`.
- **Elixir has no official Anthropic SDK**, so `Budgeteer.AI.Client` (`lib/budgeteer/ai/client.ex`) is raw HTTP via `Req` to `POST /v1/messages`, model `claude-sonnet-5`. It uses **structured outputs** (`output_config.format`, a `json_schema` requiring `transactions[]` + `currency`) rather than a "return ONLY JSON" prompt convention — a successful response is guaranteed-valid JSON, no `Jason.decode!` gamble. No `anthropic-beta` header is needed (PDF input and structured outputs are both GA now, unlike the beta header in `PLAN.md`'s original sketch). The client sits behind `Budgeteer.AI.ClientBehaviour` so `ParseWorker` depends on `Application.get_env(:budgeteer, :ai_client, Budgeteer.AI.Client)` — tests override this to `Budgeteer.AI.ClientMock` (`config/test.exs`), a `Mox` mock (new test-only dep). `config :budgeteer, :anthropic_api_key` is read from `ANTHROPIC_API_KEY` in `config/runtime.exs` (unconditional, not just the `:prod` block, so it's picked up in dev too once set) — **the user adds this key themselves**; without it, uploads still exercise the full pipeline end-to-end but land on `status: :failed` with an auth-error `error_message`, which is expected and still proves the wiring works.
- **Statement upload is a plain multipart HTML form POST, not a LiveView `allow_upload`.** The first attempt used LiveView's native channel-based upload (`allow_upload`/`live_file_input`/`consume_uploaded_entries`), which — in real testing, on the user's own machine — never completed: the entry stayed stuck at 0% and the Upload button (made conditionally `disabled` until `entry.done?` as a first fix attempt) never enabled. Root cause was never conclusively pinned down (LiveView's per-entry upload uses its own `Phoenix.Channel`, `lvu:<ref>`, joined over the *same* transport as the main LiveView socket — a plausible culprit given `app.js` sets `longPollFallbackMs: 2500`, but this couldn't be confirmed with the tooling available). Rather than keep debugging blind, the whole mechanism was replaced: `StatementLive.Upload` now renders a plain `<.form action={...} method="post" multipart>` (Phoenix.Component's `form/1`, which auto-adds the CSRF token and `enctype="multipart/form-data"`) with an ordinary `<input type="file">`, posting to a new `BudgeteerWeb.StatementController` (`POST /accounts/:account_id/statements`, plain Plug pipeline — not inside the `live_session` block, since it's a normal controller action, not a LiveView route). The controller does the SHA-256 hash + disk write + `Statements.create_statement/2` call that used to live in the LiveView. This sidesteps LiveView's upload-channel machinery entirely — no chunking, no per-entry channel join, nothing to silently fail. `Plug.Parsers`'s multipart `:length` was bumped to 20MB (default 8MB) in `endpoint.ex` to fit the 15MB file cap. **If a future upload feature is tempted to reach for `allow_upload` again, try the plain multipart form first** — it's simpler and already proven to work end-to-end (verified against the real Claude API, not just a stub) where the channel-based approach wasn't.
- **A second real bug surfaced after the multipart switch: `Plug.Parsers` (and specifically `Plug.Parsers.MULTIPART`) defaults `:read_timeout` to 15,000ms** — the max idle time allowed between socket reads while the body streams in. On the user's real machine, uploading an actual file took long enough (slow disk, or a cloud-synced folder like iCloud Drive needing to materialize the file first, etc.) that the connection was reset mid-upload with `Plug.Parsers.ParseError: ... "Read timeout"` before the file finished sending — this looked like "the request went nowhere" from the browser's side. **This is a `Plug.Parsers` plug option, not a Bandit/ThousandIsland server option** — don't go looking for `read_timeout` in `http:`/`thousand_island_options`/`http_1_options` in `config/dev.exs`, it isn't there and doesn't affect this. Fixed in `endpoint.ex`'s `plug Plug.Parsers, ...` call: `read_timeout: 120_000` alongside the existing `length: 20_000_000`. Verified directly with a raw-socket script that streams a multipart body in two halves with an 18-second pause between them — before the fix this reset the connection at ~15s; after, it correctly completed. Any future large/slow request body (not just statement uploads) benefits from this same setting.
- **A third, unrelated 15-second-default bug, on the *outbound* side this time: `Req.post` (used by `Budgeteer.AI.Client`) defaults `receive_timeout` to 15,000ms too.** Once the upload itself worked, the very first real-world test (the user's actual multi-page bank statement PDF) still failed — but this time with `%Req.TransportError{reason: :timeout}` on the `Statement`, meaning the file uploaded fine and the Oban worker ran, but Claude's response for a real multi-page document analysis + structured extraction took longer than 15s and got cut off client-side. Fixed by passing `receive_timeout: 120_000` on the `Req.post` call in `lib/budgeteer/ai/client.ex`. Verified against the user's real statement (a real 5-page PDF) end-to-end: uploaded via curl with a real authenticated session, `status` went `processing` → `processed`, and 38 real transactions were extracted into `raw_ai_output`. **Lesson for this codebase: whenever something "times out" or "goes nowhere" with no clear error, suspect a 15-second default somewhere in the stack (Plug, Req, etc.) before assuming an app-level bug** — that's now been the actual root cause twice in a row.
- **Statement processing has an explicit "processing" banner on `StatementLive.Index`**, not just a small table badge — a flash message alone (which fades) plus a badge easy to miss reads as "nothing happened" to a first-time user, per direct feedback. The index now tracks a `:processing_filenames` list (any `pending`/`processing` statement) alongside the stream and renders a spinner-icon `alert-info` banner naming them and explaining that extraction can take up to a minute and updates live via PubSub — no refresh needed. The status badge itself also gets a small spinning icon for `pending`/`processing`. **Deferred, not built**: a notification (e.g. browser push, or an in-app toast) firing specifically when processing *finishes* — flagged by the user as a "consider later" item, not requested yet.
- **The review screen's category suggestion is no longer a dead end.** A suggested category that doesn't match anything existing now has a "Create it" button next to the hint, not just static text — creating a suggestion the user can never act on defeats the point of suggesting it. Clicking it calls `Ledger.create_category/2` with the suggested name and a **type inferred from the row's own amount sign** (negative → `:expense`, positive → `:income` — no extra prompt needed), then auto-assigns the new category to *every* row sharing that same suggestion (case-insensitive), not just the one clicked — verified against the user's real statement, where six separate "Bank Fees" rows all got assigned from a single click. Category creation still never happens silently on the AI's own initiative; it's always a deliberate, one-click user action.
- **No user-facing "Claude"/"AI" wording anywhere** — it's an explicit product decision, not just a style preference: the model is an implementation detail the user should never see named in the UI. `Budgeteer.AI.*` as a module namespace and "AI" in code comments/moduledocs are fine (internal, not user-facing); flash messages, banners, and hints must not mention it. The processing banner says "extracting transactions" (not "Claude is..."), and the review screen's hint says "Suggested: ..." (not "AI suggests..."). Apply this same rule to any future user-facing copy in this app.
- **AI category suggestions.** `Budgeteer.AI.Client.parse_statement/3` takes the household's existing category names (via `Ledger.list_category_names/1`, an unscoped household-id-based lookup for the worker) and includes them in the prompt; the structured-output schema now requires a `category` string per transaction — the closest existing category name, a newly suggested one, or `""`. `StatementLive.Review` matches that name case-insensitively against `@categories` to pre-select the dropdown; when it doesn't match anything existing, the row is left "Uncategorized" with a hint ("Suggested: \"X\"" — not yet a category) rather than silently auto-creating a category — creating categories is still a manual, reviewed action.

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
  id (uuid), household_id (uuid FK), account_id (uuid FK), uploaded_by_id (uuid FK, nullable)
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

`Household` and `User` (with `household_id`/`role`/`name` fields) are built out as Ecto schemas in `Budgeteer.Households`, including registration. `Account`, `Transaction`, and `Category` are built out in `Budgeteer.Ledger` (`lib/budgeteer/ledger.ex`, `lib/budgeteer/ledger/{account,transaction,category}.ex`) with full LiveView CRUD — accounts at `/accounts`, categories at `/categories`, transactions nested at `/accounts/:account_id/transactions` (a transaction always belongs to one specific account, so its LiveViews aren't flat like Account's/Category's) and optionally tagged with a category via `transactions.category_id`. `Ledger.current_balance_cents/1` computes each account's live balance from `starting_balance_cents` + the sum of its transactions. Note: `transactions.household_id` was added via migration after the fact — see the scoping gotcha above.

`Statement` is built out in `Budgeteer.Statements` (`lib/budgeteer/statements.ex`, `lib/budgeteer/statements/{statement,parse_worker}.ex`) with LiveViews nested the same way as transactions: `/accounts/:account_id/statements` (index), `/accounts/:account_id/statements/new` (upload), `/accounts/:account_id/statements/:id/review` (confirm/edit extracted transactions). `Budgeteer.AI` (`lib/budgeteer/ai/{client,client_behaviour}.ex`) is the Claude API integration — see the Decisions section above for the full design (worker never auto-creates transactions, structured outputs, Mox-mocked in tests). `grocery_lists`/`grocery_items` are still just migrations — not yet built.

---

## Project Conventions

- Money as `bigint` cents everywhere — never floats.
- Context modules follow Phoenix conventions: `Budgeteer.Households`, `Budgeteer.Ledger` (accounts/categories/transactions), `Budgeteer.Statements`, `Budgeteer.AI`, `Budgeteer.Groceries`.
- Broadcast household-scoped writes via `Phoenix.PubSub` on topic `"household:#{household_id}"`, subscribed to in `mount/3` of relevant LiveViews.
- Oban jobs live under `Budgeteer.Statements` (e.g. `Budgeteer.Statements.ParseWorker`), queue `:statements`.
- Tests: ExUnit (as generated), plus `Mox` (test-only dep, added for `Budgeteer.AI.ClientMock` — see Decisions above). No Faker yet — add if/when seed data needs it.

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

1. Core ledger — auth ✅, registration creates a household ✅, account CRUD ✅, manual transaction entry ✅, category CRUD ✅, dashboard ✅ — invite-to-join flow **not yet built** (the only Phase 1 item remaining)
2. AI statement import ✅ — upload, `Budgeteer.AI.Client`, `ParseWorker`, review screen. Full pipeline is real (no stub); needs the user's own `ANTHROPIC_API_KEY` in the environment to actually extract transactions rather than fail at the API-auth step.
3. Real-time sync (PubSub + Presence)
4. Grocery list
5. PWA polish (manifest, service worker)
