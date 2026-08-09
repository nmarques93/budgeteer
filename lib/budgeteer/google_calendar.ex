defmodule Budgeteer.GoogleCalendar do
  @moduledoc """
  Read-only Google Calendar connection and synchronization.

  The first version imports a user's selected Google calendars into the shared
  family calendar. Imported events remain read-only in Budgeteer.
  """

  alias Budgeteer.Events
  alias Budgeteer.Households
  alias Budgeteer.Households.{Scope, User}

  @default_calendar_ids ["primary"]
  @window_before_days 365
  @window_after_days 365

  @doc "Exchanges a Google authorization code, stores the refresh token, and syncs events."
  def connect_user(%User{} = user, code, redirect_uri) do
    case client().exchange_code(code, redirect_uri) do
      {:ok, %{"refresh_token" => refresh_token, "access_token" => access_token}}
      when is_binary(refresh_token) and is_binary(access_token) ->
        with {:ok, calendars} <- client().list_calendars(access_token),
             config <- calendar_config(refresh_token, calendars),
             {:ok, user} <- Households.save_google_calendar_config(user, config),
             {:ok, count} <- sync_user(user) do
          {:ok, count}
        else
          {:error, reason} -> {:error, {:initial_sync, reason}}
        end

      {:ok, _response} ->
        {:error, {:token_exchange, :missing_refresh_token}}

      {:error, reason} ->
        {:error, {:token_exchange, reason}}
    end
  end

  @doc "Refreshes and stores the available calendars for a connected user."
  def refresh_calendars(%User{google_calendar: config} = user) when is_map(config) do
    with {:ok, %{"access_token" => access_token}} <-
           client().refresh_access_token(config["refresh_token"]),
         {:ok, calendars} <- client().list_calendars(access_token),
         {:ok, user} <-
           Households.save_google_calendar_config(user, merge_calendars(config, calendars)) do
      {:ok, user}
    else
      {:ok, _response} -> {:error, :missing_access_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def refresh_calendars(%User{}), do: {:error, :not_connected}

  @doc "Updates selected calendar IDs after validating them against the catalog."
  def select_calendars(%User{google_calendar: config} = user, calendar_ids)
      when is_map(config) and is_list(calendar_ids) do
    available_ids = config["calendars"] |> List.wrap() |> Enum.map(& &1["id"])

    if calendar_ids != [] and Enum.all?(calendar_ids, &(&1 in available_ids)) do
      Households.save_google_calendar_config(user, Map.put(config, "calendar_ids", calendar_ids))
    else
      {:error, :invalid_calendar_selection}
    end
  end

  def select_calendars(%User{}, _calendar_ids), do: {:error, :not_connected}

  @doc "Refreshes credentials and imports the configured calendars for a user."
  def sync_user(%User{google_calendar: config} = user) when is_map(config) do
    case client().refresh_access_token(config["refresh_token"]) do
      {:ok, %{"access_token" => access_token}} when is_binary(access_token) ->
        with {:ok, user} <- ensure_calendar_catalog(user, access_token),
             {:ok, count} <-
               sync_calendars(
                 Scope.for_user(user),
                 access_token,
                 user.google_calendar["calendar_ids"] || @default_calendar_ids
               ),
             {:ok, _user} <-
               Households.update_google_calendar_sync_status(
                 user,
                 DateTime.to_iso8601(DateTime.utc_now()),
                 nil
               ) do
          {:ok, count}
        else
          {:error, reason} = error ->
            _ = Households.update_google_calendar_sync_status(user, nil, safe_error(reason))
            error
        end

      {:ok, _response} ->
        error = {:error, {:token_refresh, :missing_access_token}}
        _ = Households.update_google_calendar_sync_status(user, nil, safe_error(error))
        error

      {:error, reason} ->
        error = {:error, {:token_refresh, reason}}
        _ = Households.update_google_calendar_sync_status(user, nil, safe_error(error))
        error
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
            {:error, reason} -> {:halt, {:error, {:event_import, reason}}}
          end

        {:error, reason} ->
          {:halt, {:error, {:events_fetch, calendar_id, reason}}}
      end
    end)
  end

  defp ensure_calendar_catalog(%User{google_calendar: config} = user, access_token) do
    if is_list(config["calendars"]) and config["calendars"] != [] do
      {:ok, user}
    else
      with {:ok, calendars} <- client().list_calendars(access_token),
           {:ok, user} <-
             Households.save_google_calendar_config(user, merge_calendars(config, calendars)) do
        {:ok, user}
      end
    end
  end

  defp calendar_config(refresh_token, calendars) do
    %{
      "refresh_token" => refresh_token,
      "calendar_ids" => selected_calendar_ids(calendars),
      "calendars" => normalize_calendars(calendars)
    }
  end

  defp merge_calendars(config, calendars) do
    normalized = normalize_calendars(calendars)
    available_ids = Enum.map(normalized, & &1["id"])
    selected = config["calendar_ids"] || selected_calendar_ids(normalized)
    selected = Enum.filter(selected, &(&1 in available_ids))
    selected = if selected == [], do: selected_calendar_ids(normalized), else: selected

    Map.merge(config, %{"calendars" => normalized, "calendar_ids" => selected})
  end

  defp normalize_calendars(calendars) do
    calendars
    |> Enum.filter(&is_binary(&1["id"]))
    |> Enum.map(fn calendar ->
      %{
        "id" => calendar["id"],
        "name" => calendar["summaryOverride"] || calendar["summary"] || calendar["id"],
        "primary" => calendar["primary"] == true
      }
    end)
  end

  defp selected_calendar_ids(calendars) do
    normalized = normalize_calendars(calendars)

    case Enum.find(normalized, & &1["primary"]) || List.first(normalized) do
      nil -> @default_calendar_ids
      calendar -> [calendar["id"]]
    end
  end

  defp safe_error(reason), do: inspect(reason, limit: 10, printable_limit: 500)

  defp client do
    Application.get_env(:budgeteer, :google_calendar_client, Budgeteer.GoogleCalendar.Client)
  end
end
