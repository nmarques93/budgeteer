defmodule Budgeteer.DailySummaryTest do
  use Budgeteer.DataCase

  import Mox
  import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
  import Budgeteer.LedgerFixtures
  import Budgeteer.MealsFixtures
  import Budgeteer.EventsFixtures
  import Budgeteer.GroceriesFixtures

  alias Budgeteer.DailySummary

  setup :verify_on_exit!

  describe "get_summary/1" do
    test "returns nil when nothing has been generated yet" do
      scope = household_scope_fixture()
      assert DailySummary.get_summary(scope) == nil
    end
  end

  describe "generate_summary_for_household/1" do
    test "gathers today's planned meal, over-budget categories, unchecked groceries, and today's events" do
      scope = household_scope_fixture()
      today = Date.utc_today()

      recipe = recipe_fixture(scope, %{name: "Pasta"})
      planned_meal_fixture(scope, recipe, %{date: today})

      account = account_fixture(scope, %{starting_balance: "1000.00"})
      groceries = category_fixture(scope, %{name: "Groceries", type: :expense, budget: "50.00"})

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: groceries.id,
        amount: "-80.00",
        date: today
      })

      grocery_list = grocery_list_fixture(scope)
      grocery_item_fixture(scope, grocery_list, %{name: "Milk"})
      checked = grocery_item_fixture(scope, grocery_list, %{name: "Bread"})
      Budgeteer.Groceries.check_item(scope, checked)

      event_fixture(scope, %{title: "Dentist", date: today})

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_daily_summary, fn data ->
        assert data["date"] == Date.to_iso8601(today)
        assert data["planned_meal"] == "Pasta"
        assert [category] = data["budget_categories"]
        assert category["name"] == "Groceries"
        assert category["spent"] == "-€80.00"
        assert category["budget"] == "€50.00"
        assert data["grocery_items"] == ["Milk"]
        assert data["events"] == ["Dentist"]

        {:ok, "Pasta tonight, and you're over on Groceries."}
      end)

      assert {:ok, summary} = DailySummary.generate_summary_for_household(scope.user.household_id)
      assert summary.summary == "Pasta tonight, and you're over on Groceries."
      assert summary.household_id == scope.user.household_id
      refute is_nil(summary.generated_at)

      assert DailySummary.get_summary(scope) == summary
    end

    test "omits a planned meal, budget category, or event that isn't today or isn't over budget" do
      scope = household_scope_fixture()
      today = Date.utc_today()
      tomorrow = Date.add(today, 1)

      recipe = recipe_fixture(scope)
      planned_meal_fixture(scope, recipe, %{date: tomorrow})
      event_fixture(scope, %{date: tomorrow})

      account = account_fixture(scope, %{starting_balance: "1000.00"})
      under_budget = category_fixture(scope, %{type: :expense, budget: "100.00"})

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: under_budget.id,
        amount: "-10.00",
        date: today
      })

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_daily_summary, fn data ->
        assert data["planned_meal"] == nil
        assert data["budget_categories"] == []
        assert data["events"] == []
        {:ok, "Nothing notable today."}
      end)

      assert {:ok, _summary} =
               DailySummary.generate_summary_for_household(scope.user.household_id)
    end

    test "a second call replaces the household's previous summary rather than duplicating" do
      scope = household_scope_fixture()

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_daily_summary, fn _data ->
        {:ok, "first"}
      end)

      assert {:ok, first} = DailySummary.generate_summary_for_household(scope.user.household_id)

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_daily_summary, fn _data ->
        {:ok, "second"}
      end)

      assert {:ok, second} = DailySummary.generate_summary_for_household(scope.user.household_id)

      assert first.id == second.id
      assert DailySummary.get_summary(scope).summary == "second"
    end

    test "returns an error and stores nothing when the client fails" do
      scope = household_scope_fixture()

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_daily_summary, fn _data ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               DailySummary.generate_summary_for_household(scope.user.household_id)

      assert DailySummary.get_summary(scope) == nil
    end
  end
end
