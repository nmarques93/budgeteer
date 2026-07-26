defmodule Budgeteer.LedgerFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Budgeteer.Ledger` context.
  """

  @doc """
  Generate a account.
  """
  def account_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        bank_name: "some bank_name",
        currency: "some currency",
        name: "some name",
        starting_balance: "0.42"
      })

    {:ok, account} = Budgeteer.Ledger.create_account(scope, attrs)
    account
  end

  @doc """
  Generate a transaction.
  """
  def transaction_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        amount: "0.42",
        date: ~D[2026-07-25],
        description: "some description",
        merchant: "some merchant",
        notes: "some notes",
        account_id: account_fixture(scope).id
      })

    {:ok, transaction} = Budgeteer.Ledger.create_transaction(scope, attrs)
    transaction
  end

  @doc """
  Generate a category.
  """
  def category_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        budget: "0.42",
        color: "some color",
        name: "some name #{System.unique_integer()}",
        type: :income
      })

    {:ok, category} = Budgeteer.Ledger.create_category(scope, attrs)
    category
  end
end
