defmodule Budgeteer.SubscriptionsTest do
  use Budgeteer.DataCase

  alias Budgeteer.Subscriptions

  import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
  import Budgeteer.LedgerFixtures

  defp charge(scope, account, date, opts \\ []) do
    transaction_fixture(scope, %{
      account_id: account.id,
      date: date,
      amount: Keyword.get(opts, :amount, "-9.99"),
      merchant: Keyword.get(opts, :merchant, "Netflix"),
      category_id: Keyword.get(opts, :category_id)
    })
  end

  describe "list_subscriptions/2" do
    test "detects a monthly charge: same merchant/amount, ~30-day gaps, 3+ occurrences" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      charge(scope, account, ~D[2026-05-01])
      charge(scope, account, ~D[2026-06-01])
      charge(scope, account, ~D[2026-07-01])

      assert [sub] = Subscriptions.list_subscriptions(scope)
      assert sub.merchant == "Netflix"
      assert sub.amount_cents == -999
      assert sub.cadence == :monthly
      assert sub.occurrences == 3
      assert sub.last_date == ~D[2026-07-01]
      assert sub.next_expected_date == ~D[2026-07-31]
    end

    test "detects weekly and yearly cadences" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      for date <- [~D[2026-06-01], ~D[2026-06-08], ~D[2026-06-15], ~D[2026-06-22]] do
        charge(scope, account, date, merchant: "Gym", amount: "-15.00")
      end

      for date <- [~D[2023-01-10], ~D[2024-01-10], ~D[2025-01-10]] do
        charge(scope, account, date, merchant: "Domain Renewal", amount: "-12.00")
      end

      cadences = Subscriptions.list_subscriptions(scope) |> Map.new(&{&1.merchant, &1.cadence})
      assert cadences["Gym"] == :weekly
      assert cadences["Domain Renewal"] == :yearly
    end

    test "requires at least 3 occurrences" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      charge(scope, account, ~D[2026-05-01])
      charge(scope, account, ~D[2026-06-01])

      assert Subscriptions.list_subscriptions(scope) == []
    end

    test "does not match across different amounts, even for the same merchant" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      charge(scope, account, ~D[2026-05-01], amount: "-9.99")
      charge(scope, account, ~D[2026-06-01], amount: "-10.99")
      charge(scope, account, ~D[2026-07-01], amount: "-11.99")

      assert Subscriptions.list_subscriptions(scope) == []
    end

    test "does not match irregular intervals" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      charge(scope, account, ~D[2026-05-01])
      charge(scope, account, ~D[2026-05-10])
      charge(scope, account, ~D[2026-07-20])

      assert Subscriptions.list_subscriptions(scope) == []
    end

    test "ignores income (positive amount) transactions" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      charge(scope, account, ~D[2026-05-01], amount: "1000.00", merchant: "Salary")
      charge(scope, account, ~D[2026-06-01], amount: "1000.00", merchant: "Salary")
      charge(scope, account, ~D[2026-07-01], amount: "1000.00", merchant: "Salary")

      assert Subscriptions.list_subscriptions(scope) == []
    end

    test "infers category_id from the most recent occurrence" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      category = category_fixture(scope, %{type: :expense})

      charge(scope, account, ~D[2026-05-01])
      charge(scope, account, ~D[2026-06-01])
      charge(scope, account, ~D[2026-07-01], category_id: category.id)

      assert [sub] = Subscriptions.list_subscriptions(scope)
      assert sub.category_id == category.id
    end

    test "merchant matching is case-insensitive and trims whitespace" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      charge(scope, account, ~D[2026-05-01], merchant: "netflix")
      charge(scope, account, ~D[2026-06-01], merchant: "NETFLIX")
      charge(scope, account, ~D[2026-07-01], merchant: " Netflix ")

      assert [sub] = Subscriptions.list_subscriptions(scope)
      assert sub.occurrences == 3
    end

    test "excludes dismissed patterns and only that household's dismissals apply" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      charge(scope, account, ~D[2026-05-01])
      charge(scope, account, ~D[2026-06-01])
      charge(scope, account, ~D[2026-07-01])

      assert [sub] = Subscriptions.list_subscriptions(scope)
      {:ok, _} = Subscriptions.dismiss(scope, sub.merchant_key, sub.amount_cents)

      assert Subscriptions.list_subscriptions(scope) == []
    end

    test "only detects the current household's own transactions" do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      charge(scope, account, ~D[2026-05-01])
      charge(scope, account, ~D[2026-06-01])
      charge(scope, account, ~D[2026-07-01])

      other_scope = household_scope_fixture()
      assert Subscriptions.list_subscriptions(other_scope) == []
    end
  end

  describe "dismiss/3 and undismiss/2" do
    test "dismiss/3 is idempotent" do
      scope = household_scope_fixture()
      assert {:ok, _} = Subscriptions.dismiss(scope, "netflix", -999)
      assert {:ok, _} = Subscriptions.dismiss(scope, "netflix", -999)
      assert [_one] = Subscriptions.list_dismissed(scope)
    end

    test "undismiss/2 makes the pattern detectable again" do
      scope = household_scope_fixture()
      account = account_fixture(scope)

      charge(scope, account, ~D[2026-05-01])
      charge(scope, account, ~D[2026-06-01])
      charge(scope, account, ~D[2026-07-01])

      [sub] = Subscriptions.list_subscriptions(scope)
      {:ok, dismissed} = Subscriptions.dismiss(scope, sub.merchant_key, sub.amount_cents)
      assert Subscriptions.list_subscriptions(scope) == []

      {:ok, _} = Subscriptions.undismiss(scope, dismissed)
      assert [_sub] = Subscriptions.list_subscriptions(scope)
    end
  end

  describe "monthly_equivalent_cents/1" do
    test "converts each cadence to a monthly-equivalent cost" do
      assert Subscriptions.monthly_equivalent_cents(%{amount_cents: -1200, cadence: :yearly}) ==
               -100

      assert Subscriptions.monthly_equivalent_cents(%{amount_cents: -999, cadence: :monthly}) ==
               -999

      assert Subscriptions.monthly_equivalent_cents(%{amount_cents: -300, cadence: :quarterly}) ==
               -100

      assert Subscriptions.monthly_equivalent_cents(%{amount_cents: -1000, cadence: :weekly}) <
               -4000
    end
  end
end
