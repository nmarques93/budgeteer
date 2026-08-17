# Budgeteer

A family budgeting PWA. Upload a bank statement (PDF or photo) and Claude extracts the transactions automatically — no manual entry. Everything syncs live across household members via LiveView, with shared budget categories and a real-time grocery list.

## Features

- **AI statement import** — upload a PDF/photo, review and confirm extracted transactions before anything touches the ledger
- **Real-time sync** — every household member sees the same accounts, transactions, and categories update live
- **Transaction search** — filter by date, category, merchant, or amount, across one account or the whole household
- **Budget alerts** — an email the moment a category's spend meets its budget for the month
- **Shared grocery list** — check items off together, in real time
- **Shared TODO lists** — organize household tasks, due dates, and completion in real time
- **Meal planning** — recipes with one-click "add ingredients to grocery list"
- **Dashboard** — balance history, spend vs. budget by category, category-spend breakdown
- **Household agenda** — a weekly view of calendar events, TODOs, meals, shopping, and budget alerts
- **Google sign-in**, alongside email/password and magic-link login
- **Google Calendar import** — read-only sync of a member's primary calendar into the shared calendar
- **PWA** — installable to a phone's home screen
- **MCP server** — query your household's data from an MCP client via a personal access token; write access for creating recipes and planning meals

## Stack

Elixir + Phoenix + LiveView, PostgreSQL, Oban for background jobs, the Claude API for statement parsing. See [CLAUDE.md](CLAUDE.md) for settled architecture, operational decisions, and the active hardening backlog. [PLAN.md](PLAN.md) is the historical scaffold plan.

## Local development

```bash
brew services start postgresql@17   # if not already running
mix setup                           # deps, DB, assets
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000). Statement parsing needs your own `ANTHROPIC_API_KEY` set in the environment — without it, uploads still exercise the full pipeline but land on `status: failed` with an auth error, which is expected.

## Deployment

Deployed on Fly.io — see `fly.toml` and CLAUDE.md's deployment-hardening decision for the current setup (Docker release, secrets, volume-backed statement storage, encryption key management, and liveness/readiness checks). The engineering hardening backlog in CLAUDE.md tracks the remaining external backup and restore-drill setup.
