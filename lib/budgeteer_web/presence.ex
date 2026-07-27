defmodule BudgeteerWeb.Presence do
  use Phoenix.Presence, otp_app: :budgeteer, pubsub_server: Budgeteer.PubSub
end
