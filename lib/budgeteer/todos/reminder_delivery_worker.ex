defmodule Budgeteer.Todos.ReminderDeliveryWorker do
  @moduledoc "Delivers one opt-in TODO reminder with retry support."

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Budgeteer.Households
  alias Budgeteer.Todos
  alias Budgeteer.Todos.ReminderNotifier

  @impl true
  def perform(%Oban.Job{args: %{"todo_item_id" => item_id}}) do
    item = Todos.get_item_for_reminder!(item_id)
    user = Households.get_user!(item.assignee_id)

    if user.todo_reminders_enabled and not item.completed and due?(item) do
      case ReminderNotifier.deliver_todo_reminder(user.email, user.locale, item) do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp due?(%{due_date: due_date}), do: Date.compare(due_date, Date.utc_today()) != :gt
end
