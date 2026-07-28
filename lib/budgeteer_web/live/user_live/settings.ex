defmodule BudgeteerWeb.UserLive.Settings do
  use BudgeteerWeb, :live_view

  on_mount {BudgeteerWeb.UserAuth, :require_sudo_mode}

  alias Budgeteer.Households

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>

      <div class="divider" />

      <.form for={@invite_form} id="invite_form" phx-submit="send_invite">
        <.input
          field={@invite_form[:email]}
          type="email"
          label="Invite a household member"
          placeholder="their@email.com"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Sending...">Send invite</.button>
      </.form>

      <div class="divider" />

      <div>
        <.header>
          API access
          <:subtitle>
            Personal access tokens for read-only MCP clients (Claude Desktop, etc.) to query your household's data.
          </:subtitle>
        </.header>

        <div :if={@new_token} class="alert alert-warning mt-4">
          <div>
            <p class="font-semibold">Copy your token now — you won't be able to see it again.</p>
            <p class="font-mono text-sm break-all mt-1">{@new_token}</p>
          </div>
        </div>

        <.form for={@access_token_form} id="access_token_form" phx-submit="create_access_token" class="mt-4">
          <.input
            field={@access_token_form[:name]}
            type="text"
            label="Token name"
            placeholder="e.g. Claude Desktop"
            required
          />
          <.button variant="primary" phx-disable-with="Generating...">Generate token</.button>
        </.form>

        <div class="mt-4">
          <.table id="access-tokens" rows={@access_tokens}>
            <:col :let={token} label="Name">{token.name}</:col>
            <:col :let={token} label="Created">{token.inserted_at}</:col>
            <:col :let={token} label="Last used">{token.last_used_at || "Never"}</:col>
            <:action :let={token}>
              <.button phx-click="revoke_access_token" phx-value-id={token.id} data-confirm="Revoke this token?">
                Revoke
              </.button>
            </:action>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Households.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Households.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Households.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:invite_form, to_form(%{"email" => ""}, as: "invite"))
      |> assign(:new_token, nil)
      |> assign(:access_token_form, to_form(%{"name" => ""}, as: "access_token"))
      |> assign(:access_tokens, Households.list_access_tokens(socket.assigns.current_scope))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Households.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Households.sudo_mode?(user)

    case Households.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Households.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Households.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Households.sudo_mode?(user)

    case Households.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("send_invite", %{"invite" => %{"email" => email}}, socket) do
    Households.deliver_household_invite(
      socket.assigns.current_scope.user,
      email,
      &url(~p"/users/register?#{[token: &1]}")
    )

    {:noreply,
     socket
     |> put_flash(:info, "An invite was sent to #{email}.")
     |> assign(:invite_form, to_form(%{"email" => ""}, as: "invite"))}
  end

  def handle_event("create_access_token", %{"access_token" => %{"name" => name}}, socket) do
    scope = socket.assigns.current_scope

    case Households.create_access_token(scope, name) do
      {:ok, raw_token, _access_token} ->
        {:noreply,
         socket
         |> assign(:new_token, raw_token)
         |> assign(:access_token_form, to_form(%{"name" => ""}, as: "access_token"))
         |> assign(:access_tokens, Households.list_access_tokens(scope))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't create the token — please try again.")}
    end
  end

  def handle_event("revoke_access_token", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Households.revoke_access_token(scope, id) do
      {:ok, _access_token} ->
        {:noreply,
         socket
         |> put_flash(:info, "Token revoked.")
         |> assign(:access_tokens, Households.list_access_tokens(scope))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That token no longer exists.")}
    end
  end
end
