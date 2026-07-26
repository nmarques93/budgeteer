defmodule Budgeteer.Ledger do
  @moduledoc """
  The Ledger context.
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo

  alias Budgeteer.Ledger.Account
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
      Repo.aggregate(from(t in Transaction, where: t.account_id == ^account.id), :sum, :amount_cents)

    sum_cents = if sum, do: Decimal.to_integer(sum), else: 0
    account.starting_balance_cents + sum_cents
  end

  @doc """
  Returns the list of transactions for a specific account.
  """
  def list_account_transactions(%Scope{} = scope, %Account{} = account) do
    true = account.household_id == scope.user.household_id

    Repo.all_by(Transaction, account_id: account.id, household_id: scope.user.household_id)
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
    with {:ok, transaction = %Transaction{}} <-
           %Transaction{}
           |> Transaction.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_transaction(scope, {:created, transaction})
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

    with {:ok, transaction = %Transaction{}} <-
           transaction
           |> Transaction.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_transaction(scope, {:updated, transaction})
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
end
