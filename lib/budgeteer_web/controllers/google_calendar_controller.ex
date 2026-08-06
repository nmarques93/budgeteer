defmodule BudgeteerWeb.GoogleCalendarController do
  use BudgeteerWeb, :controller

  alias Budgeteer.GoogleCalendar

  @authorization_url "https://accounts.google.com/o/oauth2/v2/auth"
  @calendar_scope "https://www.googleapis.com/auth/calendar.readonly"

  def connect(conn, _params) do
    state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    redirect_uri = url(~p"/users/settings/google-calendar/callback")

    conn
    |> put_session(:google_calendar_state, state)
    |> redirect(external: authorization_url(state, redirect_uri))
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    expected_state = get_session(conn, :google_calendar_state)

    conn = delete_session(conn, :google_calendar_state)

    if valid_state?(expected_state, state) do
      connect_calendar(conn, code)
    else
      conn
      |> put_flash(:error, gettext("Google Calendar connection could not be verified."))
      |> redirect(to: ~p"/users/settings")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, gettext("Google Calendar connection was cancelled."))
    |> redirect(to: ~p"/users/settings")
  end

  defp connect_calendar(conn, code) do
    redirect_uri = url(~p"/users/settings/google-calendar/callback")

    case GoogleCalendar.connect_user(conn.assigns.current_scope.user, code, redirect_uri) do
      {:ok, count} ->
        conn
        |> put_flash(
          :info,
          gettext("Google Calendar connected. Imported %{count} events.", count: count)
        )
        |> redirect(to: ~p"/users/settings")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Google Calendar could not be connected."))
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp authorization_url(state, redirect_uri) do
    client_id =
      Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])[:client_id] || ""

    query =
      URI.encode_query(%{
        access_type: "offline",
        client_id: client_id,
        prompt: "consent",
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: @calendar_scope,
        state: state
      })

    @authorization_url <> "?" <> query
  end

  defp valid_state?(expected, state)
       when is_binary(expected) and is_binary(state) and byte_size(expected) == byte_size(state) do
    Plug.Crypto.secure_compare(expected, state)
  end

  defp valid_state?(_expected, _state), do: false
end
