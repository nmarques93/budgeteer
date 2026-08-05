defmodule Budgeteer.InsightsTest do
  use Budgeteer.DataCase

  import Mox

  import Budgeteer.HouseholdsFixtures,
    only: [
      household_scope_fixture: 0,
      household_scope_fixture: 1,
      second_household_member_fixture: 1,
      user_fixture: 0
    ]

  import Budgeteer.LedgerFixtures

  alias Budgeteer.Insights

  setup :verify_on_exit!

  describe "get_insights/1" do
    test "returns nil when nothing has been generated yet" do
      scope = household_scope_fixture()
      assert Insights.get_insights(scope) == nil
    end
  end

  describe "generate_insights/1" do
    test "stores one localized variant for each household locale" do
      owner = user_fixture()
      member = second_household_member_fixture(owner)
      {:ok, member} = Budgeteer.Households.update_user_locale(member, "pt_PT")
      owner_scope = household_scope_fixture(owner)
      member_scope = household_scope_fixture(member)

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, 2, fn data ->
        case data["locale"] do
          "en" -> {:ok, ["English insight"]}
          "pt_PT" -> {:ok, ["Insight em português"]}
        end
      end)

      assert {:ok, english} = Insights.generate_insights(owner_scope)
      assert english.locale == "en"
      assert english.insights == ["English insight"]

      portuguese = Insights.get_insights(member_scope)
      assert portuguese.locale == "pt_PT"
      assert portuguese.insights == ["Insight em português"]
    end

    test "builds spend data from Ledger and stores the client's insights" do
      scope = household_scope_fixture()
      account = account_fixture(scope, %{starting_balance: "1000.00"})
      today = Date.utc_today()

      groceries = category_fixture(scope, %{name: "Groceries", type: :expense, budget: "50.00"})

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: groceries.id,
        amount: "-80.00",
        date: today
      })

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn data ->
        assert data["today"] == Date.to_iso8601(today)
        assert [category] = data["categories"]
        assert category["name"] == "Groceries"
        assert category["budget"] == "€50.00"
        assert category["month_to_date_spend"] == "-€80.00"

        {:ok, ["You're already over your Groceries budget this month."]}
      end)

      assert {:ok, budget_insight} = Insights.generate_insights(scope)
      assert budget_insight.insights == ["You're already over your Groceries budget this month."]
      assert budget_insight.household_id == scope.user.household_id
      refute is_nil(budget_insight.generated_at)

      assert Insights.get_insights(scope) == budget_insight
    end

    test "includes a usual_monthly_spend baseline averaged over the past 3 months, treating an absent month as zero" do
      scope = household_scope_fixture()
      account = account_fixture(scope, %{starting_balance: "1000.00"})
      today = Date.utc_today()
      category = category_fixture(scope, %{name: "Dining out", type: :expense})

      # Two of the past 3 months have €90 spent, one has none — average
      # should be (90 + 90 + 0) / 3 = 60, not (90 + 90) / 2 = 90.
      for months_back <- [1, 2] do
        date =
          Enum.reduce(1..months_back, today, fn _, acc ->
            Date.add(Date.beginning_of_month(acc), -1)
          end)

        transaction_fixture(scope, %{
          account_id: account.id,
          category_id: category.id,
          amount: "-90.00",
          date: date
        })
      end

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "-30.00",
        date: today
      })

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn data ->
        assert [row] = data["categories"]
        assert row["usual_monthly_spend"] == "-€60.00"
        {:ok, []}
      end)

      assert {:ok, _} = Insights.generate_insights(scope)
    end

    test "omits usual_monthly_spend when there's no prior history at all" do
      scope = household_scope_fixture()
      account = account_fixture(scope, %{starting_balance: "1000.00"})
      today = Date.utc_today()
      category = category_fixture(scope, %{name: "One-off", type: :expense})

      transaction_fixture(scope, %{
        account_id: account.id,
        category_id: category.id,
        amount: "-15.00",
        date: today
      })

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn data ->
        assert [row] = data["categories"]
        assert row["usual_monthly_spend"] == nil
        {:ok, []}
      end)

      assert {:ok, _} = Insights.generate_insights(scope)
    end

    test "a second call replaces the household's previous insights rather than duplicating" do
      scope = household_scope_fixture()

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn _data -> {:ok, ["first"]} end)

      assert {:ok, first} = Insights.generate_insights(scope)

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn _data ->
        {:ok, ["second"]}
      end)

      assert {:ok, second} = Insights.generate_insights(scope)

      assert first.id == second.id
      assert Insights.get_insights(scope).insights == ["second"]
    end

    test "returns an error and stores nothing when the client fails" do
      scope = household_scope_fixture()

      expect(Budgeteer.AI.DeepSeekClientMock, :generate_insights, fn _data ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Insights.generate_insights(scope)
      assert Insights.get_insights(scope) == nil
    end
  end
end
