defmodule Budgeteer.Households.DeviceToken do
  @moduledoc """
  A push-notification device token, registered by the native iOS app (see
  `mobile/`) once a user grants notification permission. Unlike
  `AccessToken`, this isn't a credential — it's just a delivery address, so
  it's stored in plaintext (same sensitivity as an email address), and the
  same physical device can legitimately re-register under a different user
  (a shared household device, or reinstalling the app), so registration is
  an upsert keyed by the token itself rather than a strict create.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "device_tokens" do
    field :token, :string
    field :platform, :string, default: "ios"
    belongs_to :user, Budgeteer.Households.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(device_token, attrs) do
    device_token
    |> cast(attrs, [:token, :platform, :user_id])
    |> validate_required([:token, :platform, :user_id])
    |> validate_length(:token, max: 512)
    |> unique_constraint(:token)
  end
end
