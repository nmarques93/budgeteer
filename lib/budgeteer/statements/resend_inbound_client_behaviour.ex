defmodule Budgeteer.Statements.ResendInboundClientBehaviour do
  @moduledoc """
  Behaviour for fetching an inbound email's attachment content from
  Resend. Lets `BudgeteerWeb.InboundEmailController` depend on a
  configured implementation (`Application.get_env(:budgeteer,
  :resend_inbound_client, Budgeteer.Statements.ResendInboundClient)`) so
  tests can swap in a Mox mock instead of making real HTTP requests.
  """

  @callback fetch_attachment(email_id :: String.t(), attachment_id :: String.t()) ::
              {:ok, %{filename: String.t(), content_type: String.t(), bytes: binary()}}
              | {:error, term()}
end
