defmodule Budgeteer.DailySummary.WorkerTest do
  use Budgeteer.DataCase
  use Oban.Testing, repo: Budgeteer.Repo

  import Mox
  import Swoosh.TestAssertions
  import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
  import Budgeteer.MealsFixtures

  alias Budgeteer.DailySummary
  alias Budgeteer.DailySummary.Worker

  setup :verify_on_exit!

  defp drain_mailbox do
    receive do
      _ -> drain_mailbox()
    after
      0 -> :ok
    end
  end

  test "generates and emails a summary for every household" do
    scope = household_scope_fixture()
    drain_mailbox()

    expect(Budgeteer.AI.DeepSeekClientMock, :generate_daily_summary, fn _data ->
      {:ok, "Nothing notable today."}
    end)

    assert :ok = perform_job(Worker, %{})

    assert DailySummary.get_summary(scope).summary == "Nothing notable today."
    assert_email_sent(subject: "Your morning summary")
  end

  test "one household's AI failure doesn't block another household's summary" do
    failing_scope = household_scope_fixture()
    succeeding_scope = household_scope_fixture()
    drain_mailbox()

    recipe = recipe_fixture(failing_scope, %{name: "FAIL_TRIGGER"})
    planned_meal_fixture(failing_scope, recipe, %{date: Date.utc_today()})

    stub(Budgeteer.AI.DeepSeekClientMock, :generate_daily_summary, fn
      %{"planned_meal" => "FAIL_TRIGGER"} -> {:error, :timeout}
      _data -> {:ok, "All good."}
    end)

    assert :ok = perform_job(Worker, %{})

    assert DailySummary.get_summary(failing_scope) == nil
    assert DailySummary.get_summary(succeeding_scope).summary == "All good."
  end

  test "generates and delivers a variant for each member locale" do
    owner = Budgeteer.HouseholdsFixtures.user_fixture()
    member = Budgeteer.HouseholdsFixtures.second_household_member_fixture(owner)
    {:ok, member} = Budgeteer.Households.update_user_locale(member, "pt_PT")
    owner_scope = Budgeteer.HouseholdsFixtures.household_scope_fixture(owner)
    member_scope = Budgeteer.HouseholdsFixtures.household_scope_fixture(member)
    drain_mailbox()

    expect(Budgeteer.AI.DeepSeekClientMock, :generate_daily_summary, 2, fn data ->
      case data["locale"] do
        "en" -> {:ok, "English summary"}
        "pt_PT" -> {:ok, "Resumo em português"}
      end
    end)

    assert :ok = perform_job(Worker, %{})
    assert DailySummary.get_summary(owner_scope).summary == "English summary"
    assert DailySummary.get_summary(member_scope).summary == "Resumo em português"
  end
end
