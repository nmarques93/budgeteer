defmodule Budgeteer.GoogleCalendar do
  @moduledoc """
  Read-only Google Calendar connection and synchronization.

  The first version imports a user's primary Google calendar into the shared
  family calendar. Imported events remain read-only in Budgeteer.
  """

  alias Budgeteer.Events
  alias Budgeteer.Households
  alias Budgeteer.Households.{Scope, User}

  @calendar_ids ["primary"]
  @window_before_days 365
  @window_after_days 365

  @doc "Exchanges a Google authorization code, stores the refresh token, and syncs events."
  def connect_user(%User{} = user, code, redirect_uri) do
    with {:ok, token_response} <- client().exchange_code(code, redirect_uri),
         refresh_token when is_binary(refresh_token) <- token_response["refresh_token"],
         {:ok, user} <- Households.save_google_calendar(user, refresh_token, @calendar_ids),
         {:ok, count} <- sync_user(user) do
      {:ok, count}
    else
      nil -> {:error, :missing_refresh_token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Refreshes credentials and imports the configured calendars for a user."
  def sync_user(%User{google_calendar: config} = user) when is_map(config) do
    with {:ok, token_response} <- client().refresh_access_token(config["refresh_token"]),
         access_token when is_binary(access_token) <- token_response["access_token"],
         {:ok, scope} <- {:ok, Scope.for_user(user)},
         {:ok, count} <-
           sync_calendars(scope, access_token, config["calendar_ids"] || @calendar_ids) do
      {:ok, count}
    else
      nil -> {:error, :missing_access_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_user(%User{}), do: {:error, :not_connected}

  defp sync_calendars(scope, access_token, calendar_ids) do
    time_min = DateTime.add(DateTime.utc_now(), -@window_before_days, :day)
    time_max = DateTime.add(DateTime.utc_now(), @window_after_days, :day)

    Enum.reduce_while(calendar_ids, {:ok, 0}, fn calendar_id, {:ok, count} ->
      case client().list_events(access_token, calendar_id, time_min, time_max) do
        {:ok, events} ->
          case Events.replace_google_events(scope, calendar_id, events) do
            {:ok, imported_count} -> {:cont, {:ok, count + imported_count}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp client do
    Application.get_env(:budgeteer, :google_calendar_client, Budgeteer.GoogleCalendar.Client)
  end
end
