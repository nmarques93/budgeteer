defmodule Budgeteer.GoogleCalendar.SyncWorker do
  @moduledoc "Synchronizes one user's connected Google Calendar."

  use Oban.Worker, queue: :calendar, max_attempts: 3

  alias Budgeteer.GoogleCalendar
  alias Budgeteer.Households

  @impl true
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    user = Households.get_user!(user_id)

    case GoogleCalendar.sync_user(user) do
      {:ok, _count} -> :ok
      {:error, :not_connected} -> :ok
      {:error, :reconnect_required} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
