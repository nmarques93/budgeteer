defmodule Budgeteer.LedgerTest do
  use Budgeteer.DataCase

  alias Budgeteer.Ledger

  describe "accounts" do
    alias Budgeteer.Ledger.Account

    import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
    import Budgeteer.LedgerFixtures

    @invalid_attrs %{name: nil, currency: nil, bank_name: nil, starting_balance_cents: nil}

    test "list_accounts/1 returns all scoped accounts" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      account = account_fixture(scope)
      other_account = account_fixture(other_scope)
      assert Ledger.list_accounts(scope) == [account]
      assert Ledger.list_accounts(other_scope) == [other_account]
    end

    test "get_account!/2 returns the account with given id" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      other_scope = household_scope_fixture()
      assert Ledger.get_account!(scope, account.id) == account
      assert_raise Ecto.NoResultsError, fn -> Ledger.get_account!(other_scope, account.id) end
    end

    test "create_account/2 with valid data creates a account" do
      valid_attrs = %{name: "some name", currency: "some currency", bank_name: "some bank_name", starting_balance_cents: 42}
      scope = household_scope_fixture()

      assert {:ok, %Account{} = account} = Ledger.create_account(scope, valid_attrs)
      assert account.name == "some name"
      assert account.currency == "some currency"
      assert account.bank_name == "some bank_name"
      assert account.starting_balance_cents == 42
      assert account.household_id == scope.user.household_id
    end

    test "create_account/2 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Ledger.create_account(scope, @invalid_attrs)
    end

    test "update_account/3 with valid data updates the account" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      update_attrs = %{name: "some updated name", currency: "some updated currency", bank_name: "some updated bank_name", starting_balance_cents: 43}

      assert {:ok, %Account{} = account} = Ledger.update_account(scope, account, update_attrs)
      assert account.name == "some updated name"
      assert account.currency == "some updated currency"
      assert account.bank_name == "some updated bank_name"
      assert account.starting_balance_cents == 43
    end

    test "update_account/3 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      account = account_fixture(scope)

      assert_raise MatchError, fn ->
        Ledger.update_account(other_scope, account, %{})
      end
    end

    test "update_account/3 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Ledger.update_account(scope, account, @invalid_attrs)
      assert account == Ledger.get_account!(scope, account.id)
    end

    test "delete_account/2 deletes the account" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      assert {:ok, %Account{}} = Ledger.delete_account(scope, account)
      assert_raise Ecto.NoResultsError, fn -> Ledger.get_account!(scope, account.id) end
    end

    test "delete_account/2 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      account = account_fixture(scope)
      assert_raise MatchError, fn -> Ledger.delete_account(other_scope, account) end
    end

    test "change_account/2 returns a account changeset" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      assert %Ecto.Changeset{} = Ledger.change_account(scope, account)
    end
  end

  describe "transactions" do
    alias Budgeteer.Ledger.Transaction

    import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
    import Budgeteer.LedgerFixtures

    @invalid_attrs %{date: nil, description: nil, amount_cents: nil, merchant: nil, notes: nil}

    test "list_transactions/1 returns all scoped transactions" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      transaction = transaction_fixture(scope)
      other_transaction = transaction_fixture(other_scope)
      assert Ledger.list_transactions(scope) == [transaction]
      assert Ledger.list_transactions(other_scope) == [other_transaction]
    end

    test "get_transaction!/2 returns the transaction with given id" do
      scope = household_scope_fixture()
      transaction = transaction_fixture(scope)
      other_scope = household_scope_fixture()
      assert Ledger.get_transaction!(scope, transaction.id) == transaction
      assert_raise Ecto.NoResultsError, fn -> Ledger.get_transaction!(other_scope, transaction.id) end
    end

    test "create_transaction/2 with valid data creates a transaction" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      valid_attrs = %{
        date: ~D[2026-07-25],
        description: "some description",
        amount_cents: 42,
        merchant: "some merchant",
        notes: "some notes",
        account_id: account.id
      }

      assert {:ok, %Transaction{} = transaction} = Ledger.create_transaction(scope, valid_attrs)
      assert transaction.date == ~D[2026-07-25]
      assert transaction.description == "some description"
      assert transaction.amount_cents == 42
      assert transaction.merchant == "some merchant"
      assert transaction.notes == "some notes"
      assert transaction.household_id == scope.user.household_id
    end

    test "create_transaction/2 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Ledger.create_transaction(scope, @invalid_attrs)
    end

    test "update_transaction/3 with valid data updates the transaction" do
      scope = household_scope_fixture()
      transaction = transaction_fixture(scope)
      update_attrs = %{date: ~D[2026-07-26], description: "some updated description", amount_cents: 43, merchant: "some updated merchant", notes: "some updated notes"}

      assert {:ok, %Transaction{} = transaction} = Ledger.update_transaction(scope, transaction, update_attrs)
      assert transaction.date == ~D[2026-07-26]
      assert transaction.description == "some updated description"
      assert transaction.amount_cents == 43
      assert transaction.merchant == "some updated merchant"
      assert transaction.notes == "some updated notes"
    end

    test "update_transaction/3 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      transaction = transaction_fixture(scope)

      assert_raise MatchError, fn ->
        Ledger.update_transaction(other_scope, transaction, %{})
      end
    end

    test "update_transaction/3 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      transaction = transaction_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Ledger.update_transaction(scope, transaction, @invalid_attrs)
      assert transaction == Ledger.get_transaction!(scope, transaction.id)
    end

    test "delete_transaction/2 deletes the transaction" do
      scope = household_scope_fixture()
      transaction = transaction_fixture(scope)
      assert {:ok, %Transaction{}} = Ledger.delete_transaction(scope, transaction)
      assert_raise Ecto.NoResultsError, fn -> Ledger.get_transaction!(scope, transaction.id) end
    end

    test "delete_transaction/2 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      transaction = transaction_fixture(scope)
      assert_raise MatchError, fn -> Ledger.delete_transaction(other_scope, transaction) end
    end

    test "change_transaction/2 returns a transaction changeset" do
      scope = household_scope_fixture()
      transaction = transaction_fixture(scope)
      assert %Ecto.Changeset{} = Ledger.change_transaction(scope, transaction)
    end
  end
end
