defmodule Budgeteer.Ledger do
  @moduledoc """
  The Ledger context.
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo

  alias Budgeteer.Ledger.{Account, Category}
  alias Budgeteer.Ledger.Transaction
  alias Budgeteer.Households.Scope

  @doc """
  Subscribes to scoped notifications about any account changes.

  The broadcasted messages match the pattern:

    * {:created, %Account{}}
    * {:updated, %Account{}}
    * {:deleted, %Account{}}

  """
  def subscribe_accounts(%Scope{} = scope) do
    key = scope.user.household_id

    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{key}:accounts")
  end

  defp broadcast_account(%Scope{} = scope, message) do
    key = scope.user.household_id

    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{key}:accounts", message)
  end

  @doc """
  Returns the list of accounts.

  ## Examples

      iex> list_accounts(scope)
      [%Account{}, ...]

  """
  def list_accounts(%Scope{} = scope) do
    Repo.all_by(Account, household_id: scope.user.household_id)
  end

  @doc """
  Gets a single account.

  Raises `Ecto.NoResultsError` if the Account does not exist.

  ## Examples

      iex> get_account!(scope, 123)
      %Account{}

      iex> get_account!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_account!(%Scope{} = scope, id) do
    Repo.get_by!(Account, id: id, household_id: scope.user.household_id)
  end

  @doc """
  Finds the account an inbound-email token belongs to, or `nil`. Unscoped
  — for the inbound-statement-email webhook, which runs outside a
  request/user context (there's no Scope to check against; the token
  itself is what identifies the account).
  """
  def get_account_by_inbound_token(token) when is_binary(token) do
    Repo.get_by(Account, inbound_email_token: token)
  end

  @doc """
  Creates a account.

  ## Examples

      iex> create_account(scope, %{field: value})
      {:ok, %Account{}}

      iex> create_account(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_account(%Scope{} = scope, attrs) do
    with {:ok, account = %Account{}} <-
           %Account{}
           |> Account.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_account(scope, {:created, account})
      {:ok, account}
    end
  end

  @doc """
  Updates a account.

  ## Examples

      iex> update_account(scope, account, %{field: new_value})
      {:ok, %Account{}}

      iex> update_account(scope, account, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_account(%Scope{} = scope, %Account{} = account, attrs) do
    true = account.household_id == scope.user.household_id

    with {:ok, account = %Account{}} <-
           account
           |> Account.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_account(scope, {:updated, account})
      {:ok, account}
    end
  end

  @doc """
  Deletes a account.

  ## Examples

      iex> delete_account(scope, account)
      {:ok, %Account{}}

      iex> delete_account(scope, account)
      {:error, %Ecto.Changeset{}}

  """
  def delete_account(%Scope{} = scope, %Account{} = account) do
    true = account.household_id == scope.user.household_id

    with {:ok, account = %Account{}} <-
           Repo.delete(account) do
      broadcast_account(scope, {:deleted, account})
      {:ok, account}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking account changes.

  ## Examples

      iex> change_account(scope, account)
      %Ecto.Changeset{data: %Account{}}

  """
  def change_account(%Scope{} = scope, %Account{} = account, attrs \\ %{}) do
    true = account.household_id == scope.user.household_id

    Account.changeset(account, attrs, scope)
  end

  @doc """
  Returns the account's current balance in cents: its starting balance plus
  the sum of all its transactions. Computed on read rather than stored, so it
  can never drift from the ledger.
  """
  def current_balance_cents(%Account{} = account) do
    sum =
      Repo.aggregate(
        from(t in Transaction, where: t.account_id == ^account.id),
        :sum,
        :amount_cents
      )

    sum_cents = if sum, do: Decimal.to_integer(sum), else: 0
    account.starting_balance_cents + sum_cents
  end

  @doc """
  Searches the household's transactions, optionally narrowed to a single
  account, by any combination of filters. Supported keys in `filters`:

    * `:account_id` — restrict to one account
    * `:category_id` — restrict to one category, or `"uncategorized"` for
      transactions with no category
    * `:query` — case-insensitive substring match against merchant,
      description, or notes
    * `:date_from` / `:date_to` — inclusive `Date` range
    * `:amount_min` / `:amount_max` — inclusive range, in cents, matched
      against the transaction's absolute amount (so a search for "around
      €45" finds both an expense and an income of that size)

  Blank/nil values are ignored. Results are ordered most recent first.
  """
  def search_transactions(%Scope{} = scope, filters \\ %{}) do
    from(t in Transaction, where: t.household_id == ^scope.user.household_id)
    |> apply_transaction_filters(filters)
    |> order_by([t], desc: t.date, desc: t.inserted_at)
    |> Repo.all()
  end

  defp apply_transaction_filters(query, filters) do
    Enum.reduce(filters, query, &apply_transaction_filter/2)
  end

  defp apply_transaction_filter({_key, nil}, query), do: query
  defp apply_transaction_filter({_key, ""}, query), do: query

  defp apply_transaction_filter({:account_id, account_id}, query),
    do: where(query, [t], t.account_id == ^account_id)

  defp apply_transaction_filter({:category_id, "uncategorized"}, query),
    do: where(query, [t], is_nil(t.category_id))

  defp apply_transaction_filter({:category_id, category_id}, query),
    do: where(query, [t], t.category_id == ^category_id)

  defp apply_transaction_filter({:query, text}, query) do
    pattern = "%#{text}%"

    where(
      query,
      [t],
      ilike(t.merchant, ^pattern) or ilike(t.description, ^pattern) or ilike(t.notes, ^pattern)
    )
  end

  defp apply_transaction_filter({:date_from, %Date{} = date}, query),
    do: where(query, [t], t.date >= ^date)

  defp apply_transaction_filter({:date_to, %Date{} = date}, query),
    do: where(query, [t], t.date <= ^date)

  defp apply_transaction_filter({:amount_min, cents}, query) when is_integer(cents),
    do: where(query, [t], fragment("abs(?)", t.amount_cents) >= ^cents)

  defp apply_transaction_filter({:amount_max, cents}, query) when is_integer(cents),
    do: where(query, [t], fragment("abs(?)", t.amount_cents) <= ^cents)

  defp validate_transaction_scope(changeset, %Scope{} = scope) do
    changeset
    |> validate_scoped_reference(:account_id, Account, scope)
    |> validate_scoped_reference(:category_id, Category, scope)
  end

  defp validate_scoped_reference(changeset, field, schema, %Scope{} = scope) do
    case Ecto.Changeset.get_field(changeset, field) do
      nil ->
        changeset

      id ->
        query =
          from record in schema,
            where: record.id == ^id and record.household_id == ^scope.user.household_id

        if Repo.exists?(query) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, field, "does not belong to this household")
        end
    end
  end

  @doc """
  Subscribes to scoped notifications about any transaction changes.

  The broadcasted messages match the pattern:

    * {:created, %Transaction{}}
    * {:updated, %Transaction{}}
    * {:deleted, %Transaction{}}

  """
  def subscribe_transactions(%Scope{} = scope) do
    key = scope.user.household_id

    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{key}:transactions")
  end

  defp broadcast_transaction(%Scope{} = scope, message) do
    key = scope.user.household_id

    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{key}:transactions", message)
  end

  @doc """
  Returns the list of transactions.

  ## Examples

      iex> list_transactions(scope)
      [%Transaction{}, ...]

  """
  def list_transactions(%Scope{} = scope) do
    Repo.all_by(Transaction, household_id: scope.user.household_id)
  end

  @doc """
  Gets a single transaction.

  Raises `Ecto.NoResultsError` if the Transaction does not exist.

  ## Examples

      iex> get_transaction!(scope, 123)
      %Transaction{}

      iex> get_transaction!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_transaction!(%Scope{} = scope, id) do
    Repo.get_by!(Transaction, id: id, household_id: scope.user.household_id)
  end

  @doc """
  Creates a transaction.

  ## Examples

      iex> create_transaction(scope, %{field: value})
      {:ok, %Transaction{}}

      iex> create_transaction(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_transaction(%Scope{} = scope, attrs) do
    changeset =
      %Transaction{}
      |> Transaction.changeset(attrs, scope)
      |> validate_transaction_scope(scope)

    with {:ok, transaction = %Transaction{}} <-
           Repo.insert(changeset) do
      broadcast_transaction(scope, {:created, transaction})
      maybe_send_budget_alert(scope, transaction.category_id)
      {:ok, transaction}
    end
  end

  @doc """
  Updates a transaction.

  ## Examples

      iex> update_transaction(scope, transaction, %{field: new_value})
      {:ok, %Transaction{}}

      iex> update_transaction(scope, transaction, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_transaction(%Scope{} = scope, %Transaction{} = transaction, attrs) do
    true = transaction.household_id == scope.user.household_id
    changeset = transaction |> Transaction.changeset(attrs, scope) |> validate_transaction_scope(scope)

    with {:ok, transaction = %Transaction{}} <-
           Repo.update(changeset) do
      broadcast_transaction(scope, {:updated, transaction})
      maybe_send_budget_alert(scope, transaction.category_id)
      {:ok, transaction}
    end
  end

  @doc """
  Deletes a transaction.

  ## Examples

      iex> delete_transaction(scope, transaction)
      {:ok, %Transaction{}}

      iex> delete_transaction(scope, transaction)
      {:error, %Ecto.Changeset{}}

  """
  def delete_transaction(%Scope{} = scope, %Transaction{} = transaction) do
    true = transaction.household_id == scope.user.household_id

    with {:ok, transaction = %Transaction{}} <-
           Repo.delete(transaction) do
      broadcast_transaction(scope, {:deleted, transaction})
      {:ok, transaction}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking transaction changes.

  ## Examples

      iex> change_transaction(scope, transaction)
      %Ecto.Changeset{data: %Transaction{}}

  """
  def change_transaction(%Scope{} = scope, %Transaction{} = transaction, attrs \\ %{}) do
    true = transaction.household_id == scope.user.household_id

    Transaction.changeset(transaction, attrs, scope)
  end

  alias Budgeteer.Ledger.Category
  alias Budgeteer.Households.Scope

  @doc """
  Subscribes to scoped notifications about any category changes.

  The broadcasted messages match the pattern:

    * {:created, %Category{}}
    * {:updated, %Category{}}
    * {:deleted, %Category{}}

  """
  def subscribe_categories(%Scope{} = scope) do
    key = scope.user.household_id

    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{key}:categories")
  end

  defp broadcast_category(%Scope{} = scope, message) do
    key = scope.user.household_id

    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{key}:categories", message)
  end

  @doc """
  Returns the list of categories.

  ## Examples

      iex> list_categories(scope)
      [%Category{}, ...]

  """
  def list_categories(%Scope{} = scope) do
    Repo.all_by(Category, household_id: scope.user.household_id)
  end

  @doc """
  Returns the category names for a household, by id (no scope). For use by
  the Statements.ParseWorker, which runs outside a request/user context and
  passes the names to the AI client so it can suggest a matching category
  per extracted transaction.
  """
  def list_category_names(household_id) do
    Repo.all(from c in Category, where: c.household_id == ^household_id, select: c.name)
  end

  @doc """
  Gets a single category.

  Raises `Ecto.NoResultsError` if the Category does not exist.

  ## Examples

      iex> get_category!(scope, 123)
      %Category{}

      iex> get_category!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_category!(%Scope{} = scope, id) do
    Repo.get_by!(Category, id: id, household_id: scope.user.household_id)
  end

  @doc """
  Gets a single category, by id (no scope). For use by
  `Budgeteer.Ledger.BudgetAlertWorker`, which runs outside a request/user
  context.
  """
  def get_category!(id) do
    Repo.get!(Category, id)
  end

  @doc """
  Creates a category.

  ## Examples

      iex> create_category(scope, %{field: value})
      {:ok, %Category{}}

      iex> create_category(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_category(%Scope{} = scope, attrs) do
    with {:ok, category = %Category{}} <-
           %Category{}
           |> Category.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_category(scope, {:created, category})
      {:ok, category}
    end
  end

  @doc """
  Updates a category.

  ## Examples

      iex> update_category(scope, category, %{field: new_value})
      {:ok, %Category{}}

      iex> update_category(scope, category, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_category(%Scope{} = scope, %Category{} = category, attrs) do
    true = category.household_id == scope.user.household_id

    with {:ok, category = %Category{}} <-
           category
           |> Category.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_category(scope, {:updated, category})
      {:ok, category}
    end
  end

  @doc """
  Deletes a category.

  ## Examples

      iex> delete_category(scope, category)
      {:ok, %Category{}}

      iex> delete_category(scope, category)
      {:error, %Ecto.Changeset{}}

  """
  def delete_category(%Scope{} = scope, %Category{} = category) do
    true = category.household_id == scope.user.household_id

    with {:ok, category = %Category{}} <-
           Repo.delete(category) do
      broadcast_category(scope, {:deleted, category})
      {:ok, category}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.

  ## Examples

      iex> change_category(scope, category)
      %Ecto.Changeset{data: %Category{}}

  """
  def change_category(%Scope{} = scope, %Category{} = category, attrs \\ %{}) do
    true = category.household_id == scope.user.household_id

    Category.changeset(category, attrs, scope)
  end

  @doc """
  Returns the household's total balance in cents, summed across all accounts.
  """
  def total_balance_cents(%Scope{} = scope) do
    scope |> list_accounts() |> Enum.map(&current_balance_cents/1) |> Enum.sum()
  end

  @doc """
  Returns per-category totals (cents spent/received) for categorized
  transactions within the given month (defaults to the current month).
  """
  def monthly_category_totals(%Scope{} = scope, date \\ Date.utc_today()) do
    monthly_category_totals_for_household(scope.user.household_id, date)
  end

  @doc """
  Same as `monthly_category_totals/2`, by household id (no scope) — same
  "background job, no user context" precedent as
  `Households.list_household_emails/1`, used by
  `Budgeteer.DailySummary.Worker`.
  """
  def monthly_category_totals_for_household(household_id, date \\ Date.utc_today()) do
    start_of_month = Date.beginning_of_month(date)
    end_of_month = Date.end_of_month(date)

    Repo.all(
      from t in Transaction,
        join: c in Category,
        on: c.id == t.category_id,
        where: t.household_id == ^household_id,
        where: t.date >= ^start_of_month and t.date <= ^end_of_month,
        group_by: [c.id, c.name, c.type, c.budget_cents],
        order_by: [asc: c.name],
        select: %{
          category_id: c.id,
          name: c.name,
          type: c.type,
          budget_cents: c.budget_cents,
          total_cents: sum(t.amount_cents)
        }
    )
  end

  @doc """
  Returns the household's most recent transactions, across all accounts.
  """
  def list_recent_transactions(%Scope{} = scope, limit \\ 10) do
    Repo.all(
      from t in Transaction,
        where: t.household_id == ^scope.user.household_id,
        order_by: [desc: t.date, desc: t.inserted_at],
        limit: ^limit
    )
  end

  @doc """
  Returns the household's total balance across all accounts for each of the
  last `days` days (default 30), oldest first — one point per day, carrying
  the previous day's balance forward on days with no transactions. Used for
  the dashboard's balance trend chart.
  """
  def balance_history(%Scope{} = scope, days \\ 30) do
    today = Date.utc_today()
    start_date = Date.add(today, -(days - 1))

    starting_total =
      scope |> list_accounts() |> Enum.map(& &1.starting_balance_cents) |> Enum.sum()

    pre_start_sum =
      Repo.aggregate(
        from(t in Transaction,
          where: t.household_id == ^scope.user.household_id and t.date < ^start_date
        ),
        :sum,
        :amount_cents
      )

    pre_start_cents = if pre_start_sum, do: Decimal.to_integer(pre_start_sum), else: 0

    daily_deltas =
      Repo.all(
        from t in Transaction,
          where: t.household_id == ^scope.user.household_id,
          where: t.date >= ^start_date and t.date <= ^today,
          group_by: t.date,
          select: {t.date, sum(t.amount_cents)}
      )
      |> Map.new(fn {date, sum} -> {date, Decimal.to_integer(sum)} end)

    {history, _final} =
      Enum.map_reduce(Date.range(start_date, today), starting_total + pre_start_cents, fn date,
                                                                                          running ->
        running = running + Map.get(daily_deltas, date, 0)
        {%{date: date, balance_cents: running}, running}
      end)

    history
  end

  # Fires once per category per month, the first time a categorized expense
  # transaction pushes that category's spend-to-date at or past its budget.
  # Dedup is an atomic conditional `update_all` (not a read-then-write) so
  # concurrent/bulk transaction creation (e.g. a statement review saving 30
  # rows at once) can't enqueue duplicate emails.
  defp maybe_send_budget_alert(_scope, nil), do: :ok

  defp maybe_send_budget_alert(%Scope{} = scope, category_id) do
    case Repo.get_by(Category, id: category_id, household_id: scope.user.household_id) do
      %Category{type: :expense, budget_cents: budget_cents} = category
      when is_integer(budget_cents) ->
        month_start = Date.beginning_of_month(Date.utc_today())
        spent_cents = category_month_spent_cents(scope, category.id, month_start)

        if spent_cents >= budget_cents do
          claim_budget_alert(category, month_start, spent_cents)
        end

      _ ->
        :ok
    end
  end

  defp category_month_spent_cents(%Scope{} = scope, category_id, month_start) do
    month_end = Date.end_of_month(month_start)

    sum =
      Repo.aggregate(
        from(t in Transaction,
          where: t.household_id == ^scope.user.household_id,
          where: t.category_id == ^category_id,
          where: t.date >= ^month_start and t.date <= ^month_end
        ),
        :sum,
        :amount_cents
      )

    case sum do
      nil -> 0
      decimal -> decimal |> Decimal.to_integer() |> abs()
    end
  end

  defp claim_budget_alert(%Category{} = category, month_start, spent_cents) do
    {claimed, _} =
      Repo.update_all(
        from(c in Category,
          where: c.id == ^category.id,
          where: is_nil(c.budget_alert_sent_for) or c.budget_alert_sent_for != ^month_start
        ),
        set: [budget_alert_sent_for: month_start]
      )

    if claimed > 0 do
      %{
        "category_id" => category.id,
        "spent_cents" => spent_cents,
        "month" => Date.to_iso8601(month_start)
      }
      |> Budgeteer.Ledger.BudgetAlertWorker.new()
      |> Oban.insert()
    end

    :ok
  end
end
