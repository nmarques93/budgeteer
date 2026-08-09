defmodule Budgeteer.GoogleCalendar.ClientBehaviour do
  @callback exchange_code(code :: String.t(), redirect_uri :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback refresh_access_token(refresh_token :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback list_calendars(access_token :: String.t()) ::
              {:ok, [map()]} | {:error, term()}
  @callback list_events(
              access_token :: String.t(),
              calendar_id :: String.t(),
              DateTime.t(),
              DateTime.t()
            ) :: {:ok, [map()]} | {:error, term()}
end
