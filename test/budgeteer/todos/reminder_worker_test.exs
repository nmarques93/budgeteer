defmodule Budgeteer.Todos.ReminderWorkerTest do
  use Budgeteer.DataCase
  use Oban.Testing, repo: Budgeteer.Repo

  import Swoosh.TestAssertions
  import Budgeteer.HouseholdsFixtures
  import Budgeteer.TodosFixtures

  alias Budgeteer.Households
  alias Budgeteer.Todos.ReminderWorker

  defp drain_mailbox do
    receive do
      _ -> drain_mailbox()
    after
      0 -> :ok
    end
  end

  test "does not email an assignee until reminders are enabled" do
    scope = household_scope_fixture()
    todo_list = todo_list_fixture(scope)

    todo_item_fixture(scope, todo_list, %{
      title: "Unsubscribed task",
      due_date: Date.utc_today(),
      assignee_id: scope.user.id
    })

    drain_mailbox()

    assert :ok = perform_job(ReminderWorker, %{})
    refute_email_sent(subject: "TODO reminder: Unsubscribed task")
  end

  test "emails an opted-in assignee for due tasks" do
    scope = household_scope_fixture()
    {:ok, _user} = Households.update_todo_reminder_preference(scope.user, true)
    todo_list = todo_list_fixture(scope)

    todo_item_fixture(scope, todo_list, %{
      title: "Pay the bill",
      due_date: Date.utc_today(),
      assignee_id: scope.user.id
    })

    drain_mailbox()

    assert :ok = perform_job(ReminderWorker, %{})
    assert_email_sent(subject: "TODO reminder: Pay the bill")
  end

  test "emails overdue tasks too" do
    scope = household_scope_fixture()
    {:ok, _user} = Households.update_todo_reminder_preference(scope.user, true)
    todo_list = todo_list_fixture(scope)

    todo_item_fixture(scope, todo_list, %{
      title: "Overdue task",
      due_date: Date.add(Date.utc_today(), -1),
      assignee_id: scope.user.id
    })

    drain_mailbox()

    assert :ok = perform_job(ReminderWorker, %{})
    assert_email_sent(subject: "TODO reminder: Overdue task")
  end
end
