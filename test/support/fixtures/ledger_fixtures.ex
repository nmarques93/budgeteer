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
        starting_balance_cents: 42
      })

    {:ok, account} = Budgeteer.Ledger.create_account(scope, attrs)
    account
  end
end
