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
end
