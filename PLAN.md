# Budgeteer — Historical Build Plan

> This document describes the original scaffold and phased build plan. It is
> retained as project history, not as the current implementation contract. See
> `CLAUDE.md` for settled architectural decisions, the current data model, and
> the active Engineering Hardening Backlog.

A family budgeting PWA built in Elixir/Phoenix. Reads bank statements via AI, syncs in real time across household members, includes a shared grocery list.

---

## Stack

| Layer | Choice | Why |
|---|---|---|
| Backend | Elixir / Phoenix | Real-time sync, PubSub, OTP supervision |
| Frontend | Phoenix LiveView (PWA) | No separate JS framework; LiveView handles real-time natively |
| Database | PostgreSQL | Reliable, good JSON support for raw AI output |
| Background jobs | Oban | Statement processing pipeline; retries, observability |
| AI | Anthropic Claude API (claude-haiku-4-5 for cost, claude-sonnet-4-6 for accuracy) | Statement parsing; handles any PDF/image format |
| Auth | phx_gen_auth | Standard, battle-tested |
| File storage | S3 (or local in dev) | Statement uploads |

---

## Data Model

```
households
  id uuid PK
  name text
  inserted_at / updated_at

users
  id uuid PK
  household_id uuid FK → households
  email text UNIQUE
  name text
  role enum (owner, member)
  -- phx_gen_auth fields

accounts
  id uuid PK
  household_id uuid FK → households
  owner_id uuid FK → users
  name text               -- e.g. "Millennium Checking"
  bank_name text
  currency char(3)        -- EUR
  balance_cents bigint    -- tracked manually, not computed
  inserted_at / updated_at

statements
  id uuid PK
  account_id uuid FK → accounts
  uploaded_by uuid FK → users
  filename text
  s3_key text
  status enum (pending, processing, processed, failed)
  raw_ai_output jsonb     -- store full Claude response for debugging
  error_message text
  inserted_at / updated_at

transactions
  id uuid PK
  account_id uuid FK → accounts
  statement_id uuid FK → statements (nullable — manual entries)
  date date
  amount_cents bigint     -- negative = debit, positive = credit
  merchant text
  description text        -- raw bank description
  category_id uuid FK → categories (nullable)
  notes text
  added_by uuid FK → users
  inserted_at / updated_at

categories
  id uuid PK
  household_id uuid FK → households
  name text
  color text              -- hex
  budget_cents bigint     -- monthly budget (nullable = unbudgeted)
  type enum (income, expense)
  inserted_at / updated_at

grocery_lists
  id uuid PK
  household_id uuid FK → households
  name text               -- "Weekly shop", "Continente run"
  archived_at timestamp   -- soft delete
  inserted_at / updated_at

grocery_items
  id uuid PK
  grocery_list_id uuid FK → grocery_lists
  name text
  quantity decimal
  unit text               -- kg, l, units
  checked boolean DEFAULT false
  added_by uuid FK → users
  checked_by uuid FK → users (nullable)
  inserted_at / updated_at
```

---

## Phoenix Project Structure

```
lib/
  budgeteer/
    households/         # Household, User context
    accounts/           # Account context (bank accounts)
    ledger/             # Transaction, Category context
    statements/         # Statement upload + Oban workers
      statement.ex
      worker.ex         # Oban job: calls Claude, parses, inserts transactions
    ai/
      client.ex         # Anthropic API wrapper (Req)
      statement_parser.ex  # builds prompt, parses response
    groceries/          # GroceryList, GroceryItem context

  budgeteer_web/
    live/
      auth/             # login, register (phx_gen_auth)
      dashboard_live.ex       # monthly summary, recent transactions
      statements_live.ex      # upload + processing status
      transactions_live.ex    # ledger view, filter/search
      categories_live.ex      # manage budget categories
      groceries_live.ex       # shared shopping list
    components/
      transaction_row.ex
      category_badge.ex
      progress_bar.ex         # budget vs actual
```

---

## PWA Setup

After `mix phx.new`, add:

1. `priv/static/manifest.json` — app name, icons, display: standalone, theme_color
2. `priv/static/sw.js` — basic service worker (cache app shell; skip caching LiveView WS)
3. Add `<link rel="manifest">` and `<meta name="theme-color">` to `root.html.heex`
4. Use `mix phx.gen.cert` for local HTTPS (PWA requires it)

---

## AI Statement Parsing

### Flow

```
User uploads PDF/image
  → StatementController stores file to S3
  → inserts Statement record (status: pending)
  → enqueues Oban job
    → Oban worker calls Anthropic Claude API with file + prompt
    → parses JSON response
    → bulk-inserts transactions
    → updates statement status: processed
    → broadcasts via PubSub to user's LiveView
```

### Claude Prompt

```elixir
defmodule Budgeteer.AI.StatementParser do
  @system_prompt """
  You are a bank statement parser. Extract all transactions from the provided
  bank statement (PDF or image). Return ONLY valid JSON, no explanation.

  Output format:
  {
    "transactions": [
      {
        "date": "YYYY-MM-DD",
        "amount_cents": -4250,
        "merchant": "Pingo Doce Foz",
        "description": "COMPRA CARTAO PINGO DOCE FOZ 15-07",
        "type": "debit"
      }
    ],
    "account_holder": "Nuno Marques",
    "statement_period": { "from": "YYYY-MM-DD", "to": "YYYY-MM-DD" },
    "currency": "EUR"
  }

  Rules:
  - amount_cents: always in cents (integer). Debits are negative, credits positive.
  - merchant: clean, human-readable merchant name extracted from the raw description.
  - description: original text from the statement, unchanged.
  - date: ISO 8601 (YYYY-MM-DD).
  - If a field is not determinable, use null.
  - Do not invent transactions. Only extract what is explicitly on the statement.
  """

  def parse(file_contents, media_type) do
    # media_type: "application/pdf" | "image/jpeg" | "image/png"
    Budgeteer.AI.Client.call(@system_prompt, file_contents, media_type)
  end
end
```

### Anthropic Client (using Req)

```elixir
defmodule Budgeteer.AI.Client do
  def call(system_prompt, file_contents, media_type) do
    encoded = Base.encode64(file_contents)

    body = %{
      model: "claude-sonnet-4-6",
      max_tokens: 4096,
      system: system_prompt,
      messages: [
        %{
          role: "user",
          content: [
            %{
              type: "document",   # use "image" for image/jpeg|png
              source: %{
                type: "base64",
                media_type: media_type,
                data: encoded
              }
            },
            %{
              type: "text",
              text: "Extract all transactions from this bank statement."
            }
          ]
        }
      ]
    }

    Req.post!(
      "https://api.anthropic.com/v1/messages",
      json: body,
      headers: [
        {"x-api-key", System.fetch_env!("ANTHROPIC_API_KEY")},
        {"anthropic-version", "2023-06-01"},
        {"anthropic-beta", "pdfs-2024-09-25"}   # required for PDF support
      ]
    )
    |> then(fn %{body: %{"content" => [%{"text" => text}]}} ->
      Jason.decode!(text)
    end)
  end
end
```

---

## Real-Time Sync (PubSub)

Broadcast on any write that should propagate to family members:

```elixir
# After inserting a transaction:
Phoenix.PubSub.broadcast(
  Budgeteer.PubSub,
  "household:#{household_id}",
  {:transaction_added, transaction}
)

# In LiveView:
def mount(_params, _session, socket) do
  Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{socket.assigns.household_id}")
  {:ok, socket}
end

def handle_info({:transaction_added, transaction}, socket) do
  {:noreply, update(socket, :transactions, &[transaction | &1])}
end
```

Same pattern for grocery list items (`:item_added`, `:item_checked`).

---

## Build Phases

### Phase 1 — Core ledger (week 1-2)
- [ ] `mix phx.new budgeteer --database postgres`
- [ ] phx_gen_auth (email/password)
- [ ] Household + invite flow (invite link with token)
- [ ] Account CRUD
- [ ] Manual transaction entry
- [ ] Category CRUD
- [ ] Basic dashboard (monthly totals per category)

### Phase 2 — AI statement import (week 3)
- [ ] Oban setup (`{:oban, "~> 2.18"}`)
- [ ] S3 upload (ex_aws or simple local storage in dev)
- [ ] Anthropic API client
- [ ] Statement worker + parsing
- [ ] Statement upload UI with processing status (PubSub → LiveView progress)
- [ ] Review screen: confirm/edit extracted transactions before saving

### Phase 3 — Real-time sync (week 4)
- [ ] PubSub broadcasts on all writes
- [ ] LiveView subscriptions
- [ ] Phoenix.Presence for "who's online" indicator
- [ ] Conflict handling (last write wins is fine for v1)

### Phase 4 — Grocery list (week 5)
- [ ] GroceryList + GroceryItem schema
- [ ] Shared list UI (real-time check/uncheck via PubSub)
- [ ] Multiple lists (archive old ones)

### Phase 5 — PWA polish
- [ ] manifest.json + service worker
- [ ] Mobile-responsive LiveView layouts
- [ ] Add to home screen prompt

---

## Key Dependencies

```elixir
# mix.exs
{:oban, "~> 2.18"},
{:req, "~> 0.5"},           # HTTP client for Anthropic API
{:ex_aws, "~> 2.5"},        # S3 uploads
{:ex_aws_s3, "~> 2.5"},
{:jason, "~> 1.4"},
{:swoosh, "~> 1.5"},        # email (invites)
```

---

## Environment Variables

```
DATABASE_URL
SECRET_KEY_BASE
ANTHROPIC_API_KEY
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_S3_BUCKET
PHX_HOST
```

---

## Notes for Claude Code

- Start with `mix phx.new budgeteer --database postgres --no-assets` (use Tailwind via CDN in dev, proper setup later)
- Run phx_gen_auth first — it touches many files and is easier before you add custom contexts
- Add Oban early (schema migration order matters)
- Use `bigint` for all money (cents) — never floats
- The AI parsing prompt above is a starting point; test against actual Portuguese bank statement PDFs (Millennium, Caixa, BPI) and adjust
- Store `raw_ai_output` on Statement — useful for debugging bad parses without re-calling the API
- The grocery list is straightforward LiveView; don't over-engineer it
