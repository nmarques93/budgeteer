defmodule Budgeteer.Ledger.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accounts" do
    field :name, :string
    field :bank_name, :string
    field :currency, :string
    field :starting_balance_cents, :integer
    field :starting_balance, :string, virtual: true
    field :inbound_email_token, :string
    field :household_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(account, attrs, household_scope) do
    account
    |> cast(attrs, [:name, :bank_name, :currency, :starting_balance])
    |> validate_required([:name, :bank_name, :currency, :starting_balance])
    |> put_starting_balance_cents()
    |> put_change(:household_id, household_scope.user.household_id)
    |> put_inbound_email_token()
  end

  # Generated once, on creation, and left alone on every later edit —
  # `get_field/2` reads the struct's existing value when there's no
  # pending change, so this only fires for a genuinely new account
  # (nil so far). Regenerating on every save would silently break any
  # forwarding rule the household already set up with their bank.
  defp put_inbound_email_token(changeset) do
    case get_field(changeset, :inbound_email_token) do
      nil -> put_change(changeset, :inbound_email_token, generate_inbound_email_token())
      _existing -> changeset
    end
  end

  defp generate_inbound_email_token do
    :crypto.strong_rand_bytes(16) |> Base.encode32(case: :lower, padding: false)
  end

  defp put_starting_balance_cents(changeset) do
    case get_change(changeset, :starting_balance) do
      nil ->
        changeset

      str ->
        case Budgeteer.Money.to_cents(str) do
          :error -> add_error(changeset, :starting_balance, "is invalid")
          cents -> put_change(changeset, :starting_balance_cents, cents)
        end
    end
  end
end
