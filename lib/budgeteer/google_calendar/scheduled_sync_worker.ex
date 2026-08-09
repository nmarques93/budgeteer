defmodule Budgeteer.GoogleCalendar.ScheduledSyncWorker do
  @moduledoc "Enqueues periodic syncs for all connected Google Calendar users."

  use Oban.Worker, queue: :calendar, max_attempts: 1

  alias Budgeteer.GoogleCalendar.SyncWorker
  alias Budgeteer.Households

  @impl true
  def perform(%Oban.Job{}) do
    Enum.reduce_while(Households.list_google_calendar_user_ids(), :ok, fn user_id, :ok ->
      job =
        SyncWorker.new(%{"user_id" => user_id},
          unique: [fields: [:args, :worker], keys: [:user_id], period: {20, :minutes}]
        )

      case Oban.insert(job) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
