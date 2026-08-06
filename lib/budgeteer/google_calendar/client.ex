defmodule Budgeteer.GoogleCalendar.Client do
  @moduledoc """
  Minimal Google Calendar API client for read-only event import.

  Authentication uses the existing Google OAuth client credentials, while the
  calendar connection requests the narrower `calendar.readonly` scope.
  """

  @behaviour Budgeteer.GoogleCalendar.ClientBehaviour

  @auth_url "https://oauth2.googleapis.com/token"
  @calendar_url "https://www.googleapis.com/calendar/v3"

  @impl true
  def exchange_code(code, redirect_uri) do
    request_token(%{
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    })
  end

  @impl true
  def refresh_access_token(refresh_token) do
    request_token(%{
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    })
  end

  @impl true
  def list_events(access_token, calendar_id, time_min, time_max) do
    fetch_events(access_token, calendar_id, time_min, time_max, nil, [])
  end

  defp request_token(params) do
    body =
      params
      |> Map.merge(%{
        client_id: client_id(),
        client_secret: client_secret()
      })

    case Req.post(@auth_url, form: body, receive_timeout: 20_000) do
      {:ok, %Req.Response{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: response}} ->
        {:error, {:http_error, status, response}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp fetch_events(access_token, calendar_id, time_min, time_max, page_token, events) do
    params = [
      timeMin: DateTime.to_iso8601(time_min),
      timeMax: DateTime.to_iso8601(time_max),
      singleEvents: "true",
      orderBy: "startTime",
      maxResults: 2500
    ]

    params = if page_token, do: [{:pageToken, page_token} | params], else: params

    case Req.get(
           "#{@calendar_url}/calendars/#{URI.encode(calendar_id)}/events",
           headers: [{"authorization", "Bearer #{access_token}"}],
           params: params,
           receive_timeout: 20_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"items" => items} = response}} ->
        all_events = events ++ items

        case response["nextPageToken"] do
          token when is_binary(token) ->
            fetch_events(access_token, calendar_id, time_min, time_max, token, all_events)

          _ ->
            {:ok, all_events}
        end

      {:ok, %Req.Response{status: status, body: response}} ->
        {:error, {:http_error, status, response}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp client_id, do: Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:client_id]

  defp client_secret,
    do: Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:client_secret]
end
