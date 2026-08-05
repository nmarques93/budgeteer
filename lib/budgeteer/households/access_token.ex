defmodule Budgeteer.Households.AccessToken do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Budgeteer.Households.AccessToken

  @hash_algorithm :sha256
  @rand_size 32
  @prefix "bgtpat_"

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "access_tokens" do
    field :name, :string
    field :token, :binary
    field :scopes, {:array, :string}, default: ["read"]
    field :last_used_at, :utc_datetime
    belongs_to :user, Budgeteer.Households.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(access_token, attrs) do
    access_token
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
  end

  @doc """
  Generates a random personal access token.

  Mirrors `UserToken`'s hashing scheme (`:crypto.strong_rand_bytes/1` +
  SHA-256 + base64url): the raw token is returned once and must be shown to
  the user immediately, since only its hash is ever persisted — it cannot
  be recovered later. Prefixed with "bgtpat_" so a leaked token is
  recognizable as belonging to this app.
  """
  def build_token do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)
    raw_token = @prefix <> Base.url_encode64(token, padding: false)

    {raw_token, hashed_token}
  end

  @doc """
  Checks whether a raw token string is well-formed and, if so, returns the
  underlying lookup query. Returns `{:ok, query}` selecting `{user,
  access_token}`, or `:error` if the token doesn't decode.

  Unlike email-delivered `UserToken`s, access tokens don't expire on their
  own — they're valid until explicitly revoked (deleted).
  """
  def verify_query(@prefix <> encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from access_token in AccessToken,
            where: access_token.token == ^hashed_token,
            join: user in assoc(access_token, :user),
            select: {user, access_token}

        {:ok, query}

      :error ->
        :error
    end
  end

  def verify_query(_raw_token), do: :error
end
