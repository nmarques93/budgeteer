defmodule Budgeteer.LedgerTest do
  use Budgeteer.DataCase

  import Swoosh.TestAssertions

  alias Budgeteer.Ledger

  describe "accounts" do
    alias Budgeteer.Ledger.Account

    import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
    import Budgeteer.LedgerFixtures

    @invalid_attrs %{name: nil, currency: nil, bank_name: nil, starting_balance: nil}

    test "list_accounts/1 returns all scoped accounts" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      account = %{account_fixture(scope) | starting_balance: nil}
      other_account = %{account_fixture(other_scope) | starting_balance: nil}
      assert Ledger.list_accounts(scope) == [account]
      assert Ledger.list_accounts(other_scope) == [other_account]
    end

    test "get_account!/2 returns the account with given id" do
      scope = household_scope_fixture()
      account = %{account_fixture(scope) | starting_balance: nil}
      other_scope = household_scope_fixture()
      assert Ledger.get_account!(scope, account.id) == account
      assert_raise Ecto.NoResultsError, fn -> Ledger.get_account!(other_scope, account.id) end
    end

    test "create_account/2 with valid data creates a account" do
      valid_attrs = %{
        name: "some name",
        currency: "some currency",
        bank_name: "some bank_name",
        starting_balance: "0.42"
      }

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

      update_attrs = %{
        name: "some updated name",
        currency: "some updated currency",
        bank_name: "some updated bank_name",
        starting_balance: "0.43"
      }

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
      account = %{account_fixture(scope) | starting_balance: nil}
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

    @invalid_attrs %{date: nil, description: nil, amount: nil, merchant: nil, notes: nil}

    test "list_transactions/1 returns all scoped transactions" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      transaction = %{transaction_fixture(scope) | amount: nil}
      other_transaction = %{transaction_fixture(other_scope) | amount: nil}
      assert Ledger.list_transactions(scope) == [transaction]
      assert Ledger.list_transactions(other_scope) == [other_transaction]
    end

    test "get_transaction!/2 returns the transaction with given id" do
      scope = household_scope_fixture()
      transaction = %{transaction_fixture(scope) | amount: nil}
      other_scope = household_scope_fixture()
      assert Ledger.get_transaction!(scope, transaction.id) == transaction

      assert_raise Ecto.NoResultsError, fn ->
        Ledger.get_transaction!(other_scope, transaction.id)
      end
    end

    test "create_transaction/2 with valid data creates a transaction" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      valid_attrs = %{
        date: ~D[2026-07-25],
        description: "some description",
        amount: "0.42",
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

      update_attrs = %{
        date: ~D[2026-07-26],
        description: "some updated description",
        amount: "0.43",
        merchant: "some updated merchant",
        notes: "some updated notes"
      }

      assert {:ok, %Transaction{} = transaction} =
               Ledger.update_transaction(scope, transaction, update_attrs)

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
      transaction = %{transaction_fixture(scope) | amount: nil}

      assert {:error, %Ecto.Changeset{}} =
               Ledger.update_transaction(scope, transaction, @invalid_attrs)

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

  describe "search_transactions/2" do
    import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
    import Budgeteer.LedgerFixtures

    test "with no filters returns every scoped transaction, most recent first" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      older = transaction_fixture(scope, %{date: ~D[2026-01-01]})
      newer = transaction_fixture(scope, %{date: ~D[2026-06-01]})
      transaction_fixture(other_scope)

      assert Ledger.search_transactions(scope) |> Enum.map(& &1.id) == [newer.id, older.id]
    end

    test "filters by date range" do
      scope = household_scope_fixture()
      jan = transaction_fixture(scope, %{date: ~D[2026-01-15]})
      transaction_fixture(scope, %{date: ~D[2026-06-15]})

      result =
        Ledger.search_transactions(scope, %{date_from: ~D[2026-01-01], date_to: ~D[2026-02-01]})

      assert Enum.map(result, & &1.id) == [jan.id]
    end

    test "filters by account_id" do
      scope = household_scope_fixture()
      account_a = account_fixture(scope)
      account_b = account_fixture(scope)
      tx_a = transaction_fixture(scope, %{account_id: account_a.id})
      transaction_fixture(scope, %{account_id: account_b.id})

      result = Ledger.search_transactions(scope, %{account_id: account_a.id})
      assert Enum.map(result, & &1.id) == [tx_a.id]
    end

    test ~s(filters by category, including "uncategorized") do
      scope = household_scope_fixture()
      category = category_fixture(scope)
      categorized = transaction_fixture(scope, %{category_id: category.id})
      uncategorized = transaction_fixture(scope)

      assert Ledger.search_transactions(scope, %{category_id: category.id}) |> Enum.map(& &1.id) ==
               [
                 categorized.id
               ]

      assert Ledger.search_transactions(scope, %{category_id: "uncategorized"})
             |> Enum.map(& &1.id) == [
               uncategorized.id
             ]
    end

    test "filters by merchant/description/notes substring, case-insensitively" do
      scope = household_scope_fixture()
      match = transaction_fixture(scope, %{merchant: "Amazon Prime"})
      transaction_fixture(scope, %{merchant: "Local Bakery"})

      assert Ledger.search_transactions(scope, %{query: "amazon"}) |> Enum.map(& &1.id) == [
               match.id
             ]
    end

    test "filters by amount range, matching on absolute value" do
      scope = household_scope_fixture()
      expense = transaction_fixture(scope, %{amount: "-45.00"})
      income = transaction_fixture(scope, %{amount: "45.00"})
      transaction_fixture(scope, %{amount: "5.00"})

      result = Ledger.search_transactions(scope, %{amount_min: 4000, amount_max: 5000})
      assert Enum.map(result, & &1.id) |> Enum.sort() == Enum.sort([expense.id, income.id])
    end

    test "blank filter values are ignored" do
      scope = household_scope_fixture()
      transaction = transaction_fixture(scope)

      result = Ledger.search_transactions(scope, %{query: "", date_from: nil, category_id: ""})
      assert Enum.map(result, & &1.id) == [transaction.id]
    end
  end

  describe "categories" do
    alias Budgeteer.Ledger.Category

    import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
    import Budgeteer.LedgerFixtures

    @invalid_attrs %{name: nil, type: nil, color: nil, budget: nil}

    test "list_categories/1 returns all scoped categories" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      category = %{category_fixture(scope) | budget: nil}
      other_category = %{category_fixture(other_scope) | budget: nil}
      assert Ledger.list_categories(scope) == [category]
      assert Ledger.list_categories(other_scope) == [other_category]
    end

    test "get_category!/2 returns the category with given id" do
      scope = household_scope_fixture()
      category = %{category_fixture(scope) | budget: nil}
      other_scope = household_scope_fixture()
      assert Ledger.get_category!(scope, category.id) == category
      assert_raise Ecto.NoResultsError, fn -> Ledger.get_category!(other_scope, category.id) end
    end

    test "create_category/2 with valid data creates a category" do
      valid_attrs = %{name: "some name", type: :income, color: "some color", budget: "0.42"}
      scope = household_scope_fixture()

      assert {:ok, %Category{} = category} = Ledger.create_category(scope, valid_attrs)
      assert category.name == "some name"
      assert category.type == :income
      assert category.color == "some color"
      assert category.budget_cents == 42
      assert category.household_id == scope.user.household_id
    end

    test "create_category/2 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Ledger.create_category(scope, @invalid_attrs)
    end

    test "update_category/3 with valid data updates the category" do
      scope = household_scope_fixture()
      category = category_fixture(scope)

      update_attrs = %{
        name: "some updated name",
        type: :expense,
        color: "some updated color",
        budget: "0.43"
      }

      assert {:ok, %Category{} = category} = Ledger.update_category(scope, category, update_attrs)
      assert category.name == "some updated name"
      assert category.type == :expense
      assert category.color == "some updated color"
      assert category.budget_cents == 43
    end

    test "update_category/3 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      category = category_fixture(scope)

      assert_raise MatchError, fn ->
        Ledger.update_category(other_scope, category, %{})
      end
    end

    test "update_category/3 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      category = %{category_fixture(scope) | budget: nil}
      assert {:error, %Ecto.Changeset{}} = Ledger.update_category(scope, category, @invalid_attrs)
      assert category == Ledger.get_category!(scope, category.id)
    end

    test "delete_category/2 deletes the category" do
      scope = household_scope_fixture()
      category = category_fixture(scope)
      assert {:ok, %Category{}} = Ledger.delete_category(scope, category)
      assert_raise Ecto.NoResultsError, fn -> Ledger.get_category!(scope, category.id) end
    end

    test "delete_category/2 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      category = category_fixture(scope)
      assert_raise MatchError, fn -> Ledger.delete_category(other_scope, category) end
    end

    test "change_category/2 returns a category changeset" do
      scope = household_scope_fixture()
      category = category_fixture(scope)
      assert %Ecto.Changeset{} = Ledger.change_category(scope, category)
    end
  end

  describe "balance_history/2" do
    import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
    import Budgeteer.LedgerFixtures

    test "returns one point per day, oldest first, ending today" do
      scope = household_scope_fixture()
      account_fixture(scope, %{starting_balance: "100.00"})

      history = Ledger.balance_history(scope, 5)

      today = Date.utc_today()
      assert Enum.map(history, & &1.date) == Enum.map(-4..0, &Date.add(today, &1))
      assert Enum.all?(history, &(&1.balance_cents == 10_000))
    end

    test "carries the starting balance forward with no transactions" do
      scope = household_scope_fixture()
      account_fixture(scope, %{starting_balance: "50.00"})

      assert Ledger.balance_history(scope, 3) |> Enum.map(& &1.balance_cents) == [
               5_000,
               5_000,
               5_000
             ]
    end

    test "applies a transaction's delta starting on its date, carried forward after" do
      scope = household_scope_fixture()
      account = account_fixture(scope, %{starting_balance: "100.00"})
      today = Date.utc_today()

      {:ok, _} =
        Ledger.create_transaction(scope, %{
          account_id: account.id,
          amount: "-20.00",
          date: Date.add(today, -1)
        })

      history = Ledger.balance_history(scope, 3)

      assert Enum.map(history, & &1.balance_cents) == [10_000, 8_000, 8_000]
    end

    test "folds a transaction before the window into the starting point" do
      scope = household_scope_fixture()
      account = account_fixture(scope, %{starting_balance: "100.00"})
      today = Date.utc_today()

      {:ok, _} =
        Ledger.create_transaction(scope, %{
          account_id: account.id,
          amount: "-30.00",
          date: Date.add(today, -10)
        })

      assert Ledger.balance_history(scope, 3) |> Enum.map(& &1.balance_cents) == [
               7_000,
               7_000,
               7_000
             ]
    end

    test "scopes to the household" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      account_fixture(scope, %{starting_balance: "100.00"})
      account_fixture(other_scope, %{starting_balance: "500.00"})

      assert Ledger.balance_history(scope, 1) == [
               %{date: Date.utc_today(), balance_cents: 10_000}
             ]
    end
  end

  describe "budget alerts" do
    import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
    import Budgeteer.LedgerFixtures

    # household_scope_fixture/0 registers (and confirms) a user, which sends
    # its own "Confirmation instructions" email — drain that stray message
    # before asserting on budget-alert emails, or assert_email_sent/
    # refute_email_sent would match against it instead.
    defp drain_mailbox do
      receive do
        _ -> drain_mailbox()
      after
        0 -> :ok
      end
    end

    test "emails every household member once spend meets the category's budget" do
      scope = household_scope_fixture()
      drain_mailbox()
      account = account_fixture(scope)
      category = category_fixture(scope, %{type: :expense, budget: "50.00"})

      Ledger.create_transaction(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "-50.00",
        date: Date.utc_today()
      })

      assert_email_sent(subject: "Budget alert: #{category.name}")

      assert Ledger.get_category!(scope, category.id).budget_alert_sent_for ==
               Date.beginning_of_month(Date.utc_today())
    end

    test "does not email while under budget" do
      scope = household_scope_fixture()
      drain_mailbox()
      account = account_fixture(scope)
      category = category_fixture(scope, %{type: :expense, budget: "50.00"})

      Ledger.create_transaction(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "-10.00",
        date: Date.utc_today()
      })

      refute_email_sent()
      assert Ledger.get_category!(scope, category.id).budget_alert_sent_for == nil
    end

    test "does not email again for a second transaction in the same month" do
      scope = household_scope_fixture()
      drain_mailbox()
      account = account_fixture(scope)
      category = category_fixture(scope, %{type: :expense, budget: "50.00"})

      Ledger.create_transaction(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "-50.00",
        date: Date.utc_today()
      })

      assert_email_sent(subject: "Budget alert: #{category.name}")

      Ledger.create_transaction(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "-10.00",
        date: Date.utc_today()
      })

      refute_email_sent()
    end

    test "does not email for income categories, even past their budget" do
      scope = household_scope_fixture()
      drain_mailbox()
      account = account_fixture(scope)
      category = category_fixture(scope, %{type: :income, budget: "50.00"})

      Ledger.create_transaction(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "100.00",
        date: Date.utc_today()
      })

      refute_email_sent()
    end

    test "does not email for a category with no budget set" do
      scope = household_scope_fixture()
      drain_mailbox()
      account = account_fixture(scope)
      category = category_fixture(scope, %{type: :expense, budget: nil})

      Ledger.create_transaction(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "-1000.00",
        date: Date.utc_today()
      })

      refute_email_sent()
    end
  end
end
