defmodule BudgeteerWeb.PushTokenController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Households

  # Called from JS running inside the native iOS app shell (see mobile/ and
  # the registration script in root.html.heex) once the user grants
  # notification permission and Capacitor's PushNotifications plugin hands
  # back an APNs device token. Plain JSON in/out, not a LiveView event —
  # this fires once on native launch, well before any LiveView has
  # necessarily mounted, and has no UI of its own.
  def create(conn, %{"token" => token}) when is_binary(token) and token != "" do
    case Households.register_device_token(conn.assigns.current_scope, token) do
      {:ok, _device_token} ->
        send_resp(conn, :no_content, "")

      {:error, _changeset} ->
        send_resp(conn, :unprocessable_entity, "")
    end
  end

  def create(conn, _params), do: send_resp(conn, :bad_request, "")
end
