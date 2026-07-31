defmodule Budgeteer.Subscriptions.DismissedSubscription do
  @moduledoc """
  Records that a household said a detected `{merchant, amount}` pattern
  isn't actually a subscription, so `Budgeteer.Subscriptions.list_subscriptions/1`
  stops surfacing it. The only persisted state in the `Subscriptions`
  context — detected subscriptions themselves are computed fresh from
  `transactions` on every call, never stored.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dismissed_subscriptions" do
    field :merchant_key, :string
    field :amount_cents, :integer
    field :household_id, :binary_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(dismissed_subscription, attrs, household_scope) do
    dismissed_subscription
    |> cast(attrs, [:merchant_key, :amount_cents])
    |> validate_required([:merchant_key, :amount_cents])
    |> put_change(:household_id, household_scope.user.household_id)
    |> unique_constraint([:household_id, :merchant_key, :amount_cents])
  end
end
