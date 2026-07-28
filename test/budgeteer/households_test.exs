defmodule Budgeteer.HouseholdsTest do
  use Budgeteer.DataCase

  alias Budgeteer.Households

  import Budgeteer.HouseholdsFixtures
  alias Budgeteer.Households.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Households.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Households.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Households.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Households.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Households.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Households.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Households.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Households.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Households.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Households.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Households.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Households.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Households.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end

    test "creates a household for the user, as owner" do
      {:ok, user} =
        Households.register_user(valid_user_attributes(household_name: "The Marques Family"))

      assert user.role == :owner
      assert %{household_id: household_id} = user
      assert household_id != nil

      household = Budgeteer.Repo.get!(Budgeteer.Households.Household, household_id)
      assert household.name == "The Marques Family"
    end

    test "requires household_name to be set" do
      {:error, changeset} = Households.register_user(%{email: unique_user_email()})
      assert %{household_name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Households.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Households.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Households.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Households.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Households.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Households.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Households.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Households.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Households.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Households.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Households.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Households.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Households.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Households.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Households.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Households.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Households.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Households.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Households.generate_user_session_token(user)

      {:ok, {_, _}} =
        Households.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Households.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Households.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Households.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Households.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Households.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Households.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Households.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Households.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Households.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Households.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Households.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Households.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture()
      {1, nil} = Repo.update_all(User, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Households.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Households.generate_user_session_token(user)
      assert Households.delete_user_session_token(token) == :ok
      refute Households.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Households.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "deliver_household_invite/3" do
    setup do
      %{inviter: user_fixture()}
    end

    test "sends token through notification", %{inviter: inviter} do
      invitee_email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Households.deliver_household_invite(inviter, invitee_email, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == inviter.id
      assert user_token.sent_to == invitee_email
      assert user_token.context == "household_invite"
    end
  end

  describe "get_household_invite/1" do
    setup do
      inviter = user_fixture()
      invitee_email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Households.deliver_household_invite(inviter, invitee_email, url)
        end)

      %{inviter: inviter, invitee_email: invitee_email, token: token}
    end

    test "resolves a valid token to the inviter's household and the invitee email", %{
      inviter: inviter,
      invitee_email: invitee_email,
      token: token
    } do
      assert {:ok, household, ^invitee_email} = Households.get_household_invite(token)
      assert household.id == inviter.household_id
    end

    test "rejects a garbage token" do
      assert Households.get_household_invite("not-a-real-token") == :error
    end

    test "rejects an expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Households.get_household_invite(token) == :error
    end
  end

  describe "register_invited_user/2" do
    test "joins the given household as a member, without creating a new one" do
      inviter = user_fixture()
      household = Repo.get!(Budgeteer.Households.Household, inviter.household_id)
      email = unique_user_email()

      assert {:ok, user} = Households.register_invited_user(%{email: email}, household)
      assert user.household_id == household.id
      assert user.role == :member
      assert Repo.aggregate(Budgeteer.Households.Household, :count) == 1
    end

    test "requires a valid email" do
      inviter = user_fixture()
      household = Repo.get!(Budgeteer.Households.Household, inviter.household_id)

      {:error, changeset} = Households.register_invited_user(%{email: "not valid"}, household)
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end
  end

  describe "find_or_create_oauth_user/2" do
    defp oauth_auth(email, name \\ "Ada Lovelace") do
      %Ueberauth.Auth{
        uid: "google-#{email}",
        provider: :google,
        info: %Ueberauth.Auth.Info{email: email, name: name}
      }
    end

    test "logs in an existing user with a matching email, invite or not" do
      %{id: id} = user = user_fixture()
      assert {:ok, %User{id: ^id}} = Households.find_or_create_oauth_user(oauth_auth(user.email))
    end

    test "creates a new household as owner when there's no existing user and no invite" do
      email = unique_user_email()

      assert {:ok, user} = Households.find_or_create_oauth_user(oauth_auth(email, "Ada Lovelace"))
      assert user.email == email
      assert user.name == "Ada Lovelace"
      assert user.role == :owner
      assert user.confirmed_at

      household = Repo.get!(Budgeteer.Households.Household, user.household_id)
      assert household.name == "Ada Lovelace's Household"
    end

    test "joins the inviting household as a member when the invite email matches" do
      inviter = user_fixture()
      invitee_email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Households.deliver_household_invite(inviter, invitee_email, url)
        end)

      assert {:ok, user} = Households.find_or_create_oauth_user(oauth_auth(invitee_email), token)
      assert user.household_id == inviter.household_id
      assert user.role == :member
      assert user.confirmed_at
    end

    test "falls back to a new household when the invite email doesn't match" do
      inviter = user_fixture()
      invitee_email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Households.deliver_household_invite(inviter, invitee_email, url)
        end)

      other_email = unique_user_email()
      assert {:ok, user} = Households.find_or_create_oauth_user(oauth_auth(other_email), token)
      assert user.household_id != inviter.household_id
      assert user.role == :owner
    end

    test "creates a new household when the invite token is invalid" do
      email = unique_user_email()
      assert {:ok, user} = Households.find_or_create_oauth_user(oauth_auth(email), "garbage")
      assert user.role == :owner
    end
  end

  describe "access tokens" do
    test "create_access_token/2 returns a usable raw token and persists only its hash" do
      user = user_fixture()
      scope = Budgeteer.Households.Scope.for_user(user)

      assert {:ok, raw_token, access_token} = Households.create_access_token(scope, "Claude Desktop")
      assert String.starts_with?(raw_token, "bgtpat_")
      assert access_token.name == "Claude Desktop"
      assert access_token.token != raw_token
      assert Households.get_user_by_access_token(raw_token).id == user.id
    end

    test "create_access_token/2 requires a name" do
      user = user_fixture()
      scope = Budgeteer.Households.Scope.for_user(user)

      assert {:error, changeset} = Households.create_access_token(scope, "")
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "list_access_tokens/1 scopes to the current user" do
      user = user_fixture()
      other_user = user_fixture()
      scope = Budgeteer.Households.Scope.for_user(user)
      other_scope = Budgeteer.Households.Scope.for_user(other_user)

      {:ok, _, first} = Households.create_access_token(scope, "First")
      {:ok, _, second} = Households.create_access_token(scope, "Second")
      {:ok, _, _other} = Households.create_access_token(other_scope, "Someone else's")

      assert Households.list_access_tokens(scope) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([first.id, second.id])
    end

    test "revoke_access_token/2 deletes the token and is scoped to its owner" do
      user = user_fixture()
      other_user = user_fixture()
      scope = Budgeteer.Households.Scope.for_user(user)
      other_scope = Budgeteer.Households.Scope.for_user(other_user)

      {:ok, raw_token, access_token} = Households.create_access_token(scope, "Claude Desktop")

      assert {:error, :not_found} = Households.revoke_access_token(other_scope, access_token.id)
      assert Households.get_user_by_access_token(raw_token)

      assert {:ok, _} = Households.revoke_access_token(scope, access_token.id)
      refute Households.get_user_by_access_token(raw_token)
    end

    test "get_user_by_access_token/1 returns nil for garbage or unknown tokens" do
      refute Households.get_user_by_access_token("garbage")
      refute Households.get_user_by_access_token("bgtpat_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false))
    end

    test "get_user_by_access_token/1 touches last_used_at" do
      user = user_fixture()
      scope = Budgeteer.Households.Scope.for_user(user)
      {:ok, raw_token, access_token} = Households.create_access_token(scope, "Claude Desktop")

      refute access_token.last_used_at

      assert Households.get_user_by_access_token(raw_token)

      [reloaded] = Households.list_access_tokens(scope)
      assert reloaded.last_used_at
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
