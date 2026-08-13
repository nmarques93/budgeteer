defmodule Budgeteer.Todos.ReminderWorker do
  @moduledoc "Enqueues opt-in email reminders for due and overdue TODOs."

  use Oban.Worker, queue: :notifications, max_attempts: 1

  alias Budgeteer.Todos
  alias Budgeteer.Todos.ReminderDeliveryWorker

  @impl true
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    Enum.reduce_while(Todos.list_reminder_items(today), :ok, fn item, :ok ->
      job =
        ReminderDeliveryWorker.new(
          %{
            "todo_item_id" => item.id,
            "assignee_id" => item.assignee_id,
            "dedupe_key" =>
              "todo-reminder:#{item.id}:#{item.assignee_id}:#{Date.to_iso8601(today)}"
          },
          unique: [fields: [:args, :worker], keys: [:dedupe_key], period: :infinity]
        )

      case Oban.insert(job) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
