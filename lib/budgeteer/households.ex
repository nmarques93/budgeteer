defmodule Budgeteer.Households do
  @moduledoc """
  The Households context.
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo

  alias Budgeteer.Households.{
    Household,
    User,
    UserToken,
    UserNotifier,
    AccessToken,
    DeviceToken,
    Scope
  }

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Returns every member's email + locale for a household, by id (no scope).
  For use by contexts like `Budgeteer.Ledger` that need to notify a whole
  household (e.g. a budget alert) rather than a single scoped user — the
  locale lets each notification go out in that member's own saved language
  preference, not whatever locale happens to be active in the sending
  process.
  """
  def list_household_emails(household_id) do
    Repo.all(
      from u in User,
        where: u.household_id == ^household_id,
        select: %{email: u.email, locale: u.locale}
    )
  end

  @doc "Returns members who explicitly opted into daily-summary email."
  def list_daily_summary_emails(household_id) do
    Repo.all(
      from u in User,
        where: u.household_id == ^household_id and u.daily_summary_email_enabled == true,
        select: %{user_id: u.id, email: u.email, locale: u.locale}
    )
  end

  @doc "Updates the current user's daily-summary email preference."
  def update_daily_summary_email_preference(%User{} = user, enabled)
      when is_boolean(enabled) do
    user
    |> Ecto.Changeset.change(daily_summary_email_enabled: enabled)
    |> Repo.update()
  end

  @doc "Updates the current user's TODO reminder email preference."
  def update_todo_reminder_preference(%User{} = user, enabled) when is_boolean(enabled) do
    user
    |> Ecto.Changeset.change(todo_reminders_enabled: enabled)
    |> Repo.update()
  end

  @doc "Returns the supported locales used by members of a household."
  def list_household_locales(household_id) do
    locales =
      Repo.all(
        from u in User,
          where: u.household_id == ^household_id,
          select: u.locale
      )
      |> Enum.map(&(&1 || "en"))
      |> Enum.filter(&(&1 in ~w(en pt_PT)))
      |> Enum.uniq()

    if locales == [], do: ["en"], else: locales
  end

  @doc """
  Returns every household's id — for a scheduled job (like
  `Budgeteer.DailySummary.Worker`) that needs to run once per household,
  not once per request/user.
  """
  def list_household_ids do
    Repo.all(from h in Household, select: h.id)
  end

  @doc "Returns user IDs with a connected Google Calendar for scheduled syncs."
  def list_google_calendar_user_ids do
    Repo.all(from u in User, where: not is_nil(u.google_calendar), select: u.id)
  end

  @doc """
  Returns every member of the current scope's household, ordered by name
  (falling back to email — `name` is optional, e.g. for a password
  registration that never set one). Used to color-code and assign calendar
  events per person.
  """
  def list_household_members(%Scope{} = scope) do
    Repo.all(
      from u in User,
        where: u.household_id == ^scope.user.household_id,
        order_by: [asc: fragment("coalesce(?, ?)", u.name, u.email)]
    )
  end

  ## Households

  @doc """
  Creates a household.
  """
  def create_household(attrs) do
    %Household{}
    |> Household.changeset(attrs)
    |> Repo.insert()
  end

  ## User registration

  @doc """
  Registers a user, creating a new household for them (as owner) in the
  same transaction.

  ## Examples

      iex> register_user(%{email: value, household_name: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    changeset = User.registration_changeset(%User{}, attrs)

    if changeset.valid? do
      Repo.transact(fn ->
        with {:ok, household} <-
               create_household(%{name: Ecto.Changeset.get_field(changeset, :household_name)}),
             {:ok, user} <-
               changeset
               |> Ecto.Changeset.put_change(:household_id, household.id)
               |> Ecto.Changeset.put_change(:role, :owner)
               |> Repo.insert() do
          {:ok, user}
        end
      end)
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for registration.

  See `Budgeteer.Households.User.registration_changeset/3` for supported options.
  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  @doc """
  Registers a user who is joining an existing household via an invite,
  instead of creating a new household.

  ## Examples

      iex> register_invited_user(%{field: value}, household)
      {:ok, %User{}}

      iex> register_invited_user(%{field: bad_value}, household)
      {:error, %Ecto.Changeset{}}

  """
  def register_invited_user(attrs, %Household{} = household) do
    changeset = User.invite_registration_changeset(%User{}, attrs)

    if changeset.valid? do
      changeset
      |> Ecto.Changeset.put_change(:household_id, household.id)
      |> Ecto.Changeset.put_change(:role, :member)
      |> Repo.insert()
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for registering via a household invite.

  See `Budgeteer.Households.User.invite_registration_changeset/3` for
  supported options.
  """
  def change_invited_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.invite_registration_changeset(user, attrs, opts)
  end

  @doc """
  Finds or creates a user from an OAuth callback (Google, etc.), reconciling
  against any pending household invite token.

  Google-verified email ownership is treated as the same trust level the
  app already extends to magic-link login (anyone with access to the
  inbox) — an existing user with a matching email is logged straight in,
  with no separate "link this account" confirmation step.

  * Existing user with this email → `{:ok, user}`, as-is.
  * No existing user, `invite_token` resolves to an invite sent to this
    exact email → joins that household as `:member`.
  * No existing user, no matching invite → creates a new household and
    joins it as `:owner`, named after the user (there's no interactive
    naming step for this path).

  OAuth-created users are confirmed immediately, since Google already
  verified the email.
  """
  def find_or_create_oauth_user(%Ueberauth.Auth{} = auth, invite_token \\ nil) do
    email = auth.info.email
    name = auth.info.name

    case get_user_by_email(email) do
      %User{} = user ->
        record_oauth_provider(user)

      nil ->
        case resolve_matching_invite(invite_token, email) do
          {:ok, household} -> create_oauth_invited_user(email, name, household)
          :error -> create_oauth_owner_user(email, name)
        end
    end
  end

  defp resolve_matching_invite(nil, _email), do: :error

  defp resolve_matching_invite(token, email) do
    case get_household_invite(token) do
      {:ok, household, ^email} -> {:ok, household}
      _ -> :error
    end
  end

  defp create_oauth_invited_user(email, name, %Household{} = household) do
    changeset = User.oauth_registration_changeset(%User{}, %{email: email, name: name})

    if changeset.valid? do
      changeset
      |> Ecto.Changeset.put_change(:household_id, household.id)
      |> Ecto.Changeset.put_change(:role, :member)
      |> Ecto.Changeset.put_change(:auth_providers, ["google"])
      |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
      |> Repo.insert()
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  defp create_oauth_owner_user(email, name) do
    changeset = User.oauth_registration_changeset(%User{}, %{email: email, name: name})

    if changeset.valid? do
      Repo.transact(fn ->
        with {:ok, household} <- create_household(%{name: "#{name || email}'s Household"}),
             {:ok, user} <-
               changeset
               |> Ecto.Changeset.put_change(:household_id, household.id)
               |> Ecto.Changeset.put_change(:role, :owner)
               |> Ecto.Changeset.put_change(:auth_providers, ["google"])
               |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
               |> Repo.insert() do
          {:ok, user}
        end
      end)
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  defp record_oauth_provider(%User{auth_providers: providers} = user) do
    if "google" in providers do
      {:ok, user}
    else
      user
      |> Ecto.Changeset.change(auth_providers: Enum.uniq(["google" | providers]))
      |> Repo.update()
    end
  end

  ## Settings

  @doc "Returns whether the scoped user is the household owner."
  def owner?(%Scope{user: %User{role: :owner}}), do: true
  def owner?(%Scope{}), do: false

  @doc "Returns `:ok` for owners and `{:error, :forbidden}` for members."
  def require_owner(%Scope{} = scope) do
    if owner?(scope), do: :ok, else: {:error, :forbidden}
  end

  @doc "Stores a user's encrypted Google Calendar refresh-token configuration."
  def save_google_calendar(%User{} = user, refresh_token, calendar_ids)
      when is_binary(refresh_token) and is_list(calendar_ids) do
    save_google_calendar_config(user, %{
      "refresh_token" => refresh_token,
      "calendar_ids" => calendar_ids
    })
  end

  @doc "Stores an encrypted Google Calendar configuration map."
  def save_google_calendar_config(%User{} = user, config) when is_map(config) do
    user
    |> Ecto.Changeset.change(google_calendar: config)
    |> Repo.update()
  end

  @doc "Records the last Google Calendar sync result without exposing provider tokens."
  def update_google_calendar_sync_status(%User{} = user, last_synced_at, last_sync_error) do
    config = user.google_calendar || %{}

    config =
      config
      |> Map.put("last_synced_at", last_synced_at)
      |> Map.put("last_sync_error", last_sync_error)

    save_google_calendar_config(user, config)
  end

  @doc "Disconnects the user's Google Calendar integration."
  def disconnect_google_calendar(%User{} = user) do
    user |> Ecto.Changeset.change(google_calendar: nil) |> Repo.update()
  end

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Budgeteer.Households.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Budgeteer.Households.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Sets the user's locale preference (e.g. from the language switcher), so it
  follows them across devices/sessions. Never fed untrusted form input, so
  no changeset validation is needed — same precedent as `Statement.status`.
  """
  def update_user_locale(%User{} = user, locale) when is_binary(locale) do
    user
    |> Ecto.Changeset.change(locale: locale)
    |> Repo.update()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Delivers a household invite to the given email, on behalf of the inviter.
  """
  def deliver_household_invite(%User{} = inviter, invitee_email, invite_url_fun)
      when is_function(invite_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_household_invite_token(inviter, invitee_email)
    Repo.insert!(user_token)

    UserNotifier.deliver_household_invite_instructions(
      inviter,
      invitee_email,
      invite_url_fun.(encoded_token)
    )
  end

  @doc """
  Resolves a household invite token to the household the invite is for and
  the email it was sent to.

  Returns `{:ok, household, invitee_email}` or `:error` if the token is
  missing, malformed, or expired.
  """
  def get_household_invite(token) do
    with {:ok, query} <- UserToken.verify_household_invite_token_query(token),
         {inviter, user_token} <- Repo.one(query) do
      {:ok, Repo.get!(Household, inviter.household_id), user_token.sent_to}
    else
      _ -> :error
    end
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Access tokens (personal access tokens for the read-only MCP server)

  @doc """
  Creates a personal access token for the scoped user.

  Returns `{:ok, raw_token, %AccessToken{}}` — the raw token is only ever
  available here, at creation time. Only its hash is persisted, so it must
  be shown to the user immediately and can never be recovered later.
  """
  def create_access_token(%Scope{} = scope, name, scopes \\ ["read"]) do
    {raw_token, hashed_token} = AccessToken.build_token()
    scopes = normalize_access_token_scopes(scopes)

    changeset = AccessToken.changeset(%AccessToken{}, %{name: name})

    cond do
      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      not valid_access_token_scopes?(scope, scopes) ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(:name, "has invalid or unauthorized scopes")
         |> Map.put(:action, :insert)}

      true ->
        changeset
        |> Ecto.Changeset.put_change(:token, hashed_token)
        |> Ecto.Changeset.put_change(:user_id, scope.user.id)
        |> Ecto.Changeset.put_change(:scopes, scopes)
        |> Repo.insert()
        |> case do
          {:ok, access_token} -> {:ok, raw_token, access_token}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc "The scopes supported by personal access tokens."
  def access_token_scopes, do: ["read", "meal_write"]

  defp normalize_access_token_scopes(scopes) when is_list(scopes) do
    scopes
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp normalize_access_token_scopes(_scopes), do: []

  defp valid_access_token_scopes?(scope, scopes) do
    scopes != [] and
      Enum.all?(scopes, &(&1 in access_token_scopes())) and
      (owner?(scope) or scopes == ["read"])
  end

  @doc """
  Returns the scoped user's access tokens, newest first.
  """
  def list_access_tokens(%Scope{} = scope) do
    Repo.all(
      from a in AccessToken,
        where: a.user_id == ^scope.user.id,
        order_by: [desc: a.inserted_at]
    )
  end

  @doc """
  Revokes (deletes) an access token, scoped to the given user — one user
  can never revoke another user's token.
  """
  def revoke_access_token(%Scope{} = scope, id) do
    case Repo.get_by(AccessToken, id: id, user_id: scope.user.id) do
      nil -> {:error, :not_found}
      access_token -> Repo.delete(access_token)
    end
  end

  @doc """
  Looks up the user for a raw access token string, touching `last_used_at`
  on success. Returns `nil` for a malformed, unknown, or revoked token.
  """
  def get_user_by_access_token(raw_token) when is_binary(raw_token) do
    case get_user_and_access_token_by_access_token(raw_token) do
      {user, _access_token} -> user
      nil -> nil
    end
  end

  @doc "Looks up a token owner and the token's scopes, touching last-used time."
  def get_user_and_access_token_by_access_token(raw_token) when is_binary(raw_token) do
    with {:ok, query} <- AccessToken.verify_query(raw_token),
         {user, access_token} <- Repo.one(query) do
      access_token
      |> Ecto.Changeset.change(last_used_at: DateTime.utc_now(:second))
      |> Repo.update()

      {user, access_token}
    else
      _ -> nil
    end
  end

  ## Device tokens (push notifications for the native iOS app — see mobile/)

  @doc """
  Registers (or re-registers) a push-notification device token for the
  scoped user. Upserts by the token itself, not by user — the same
  physical device might re-register under a different household member
  (a shared device, or a reinstall), in which case ownership should simply
  move to whoever's currently signed in, not error out on the existing row.
  """
  def register_device_token(%Scope{} = scope, token, platform \\ "ios") when is_binary(token) do
    attrs = %{token: token, platform: platform, user_id: scope.user.id}

    case Repo.get_by(DeviceToken, token: token) do
      nil -> DeviceToken.changeset(%DeviceToken{}, attrs)
      existing -> DeviceToken.changeset(existing, attrs)
    end
    |> Repo.insert_or_update()
  end

  @doc """
  Returns every push token registered to a household, by id (no scope),
  paired with that token owner's own locale — same "background job, no
  user context" precedent as `list_household_emails/1`, and the same
  reason it carries locale too: `Ledger.BudgetAlertWorker` fans a push out
  to every member, and each one should read it in their own saved
  language, not whatever locale happens to be active in the job process.
  """
  def list_household_device_tokens(household_id) do
    Repo.all(
      from d in DeviceToken,
        join: u in assoc(d, :user),
        where: u.household_id == ^household_id,
        select: %{token: d.token, locale: u.locale}
    )
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
