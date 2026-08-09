defmodule BudgeteerWeb.UserLive.Settings do
  use BudgeteerWeb, :live_view

  on_mount {BudgeteerWeb.UserAuth, :require_sudo_mode}

  alias Budgeteer.Households
  alias Budgeteer.Events
  alias Budgeteer.GoogleCalendar
  alias Budgeteer.GoogleCalendar.SyncWorker
  alias Budgeteer.RateLimit

  @invite_scale :timer.hours(1)
  @invite_limit 10
  @access_token_scale :timer.hours(1)
  @access_token_limit 10

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <div class="text-center">
        <.header>
          {gettext("Account Settings")}
          <:subtitle>{gettext("Manage your account email address and password settings")}</:subtitle>
        </.header>
      </div>

      <%= if @email_auth_enabled do %>
        <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
          <.input
            field={@email_form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button variant="primary" phx-disable-with={gettext("Changing...")}>
            {gettext("Change Email")}
          </.button>
        </.form>
      <% end %>

      <%= if @password_auth_enabled do %>
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
            label={gettext("New password")}
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            autocomplete="new-password"
            spellcheck="false"
          />
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save Password")}
          </.button>
        </.form>
      <% end %>

      <p :if={!@email_auth_enabled && !@password_auth_enabled} class="alert alert-info">
        {gettext(
          "Your account is managed through Google. Email and password settings are unavailable here."
        )}
      </p>

      <div class="divider" />

      <.form
        :if={@current_scope.user.role == :owner}
        for={@invite_form}
        id="invite_form"
        phx-submit="send_invite"
      >
        <.input
          field={@invite_form[:email]}
          type="email"
          label={gettext("Invite a household member")}
          placeholder="their@email.com"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with={gettext("Sending...")}>
          {gettext("Send invite")}
        </.button>
      </.form>

      <div class="divider" />

      <div>
        <.header>
          {gettext("Google Calendar")}
          <:subtitle>
            {gettext("Import your primary Google Calendar into the shared household calendar.")}
          </:subtitle>
        </.header>

        <%= if @google_calendar_connected do %>
          <div class="flex flex-wrap items-center gap-2 mt-4">
            <span class="text-success">{gettext("Connected")}</span>
            <.button phx-click="refresh_google_calendars" phx-disable-with={gettext("Loading...")}>
              {gettext("Refresh calendars")}
            </.button>
            <.button phx-click="sync_google_calendar" phx-disable-with={gettext("Syncing...")}>
              {gettext("Sync now")}
            </.button>
            <.button
              phx-click="disconnect_google_calendar"
              data-confirm={gettext("Disconnect Google Calendar?")}
            >
              {gettext("Disconnect")}
            </.button>
          </div>
          <p :if={@google_calendar_last_sync_error} class="text-error text-sm mt-2">
            {gettext("Last sync failed: %{error}", error: @google_calendar_last_sync_error)}
          </p>
          <p :if={@google_calendar_last_synced_at} class="text-sm opacity-70 mt-2">
            {gettext("Last synced: %{time}", time: @google_calendar_last_synced_at)}
          </p>
          <form
            :if={@google_calendar_calendars != []}
            id="google-calendar-selection-form"
            phx-submit="save_google_calendar_selection"
            class="mt-3"
          >
            <p class="text-sm font-semibold mb-1">{gettext("Calendars to import")}</p>
            <.input
              :for={calendar <- @google_calendar_calendars}
              name="calendar_ids[]"
              type="checkbox"
              value={calendar["id"]}
              checked={calendar["id"] in @google_calendar_ids}
              label={calendar["name"]}
            />
            <.button variant="primary" phx-disable-with={gettext("Saving...")}>
              {gettext("Save calendars")}
            </.button>
          </form>
        <% else %>
          <.link href={~p"/users/settings/google-calendar/connect"} class="btn btn-primary mt-4">
            {gettext("Connect Google Calendar")}
          </.link>
        <% end %>
      </div>

      <div class="divider" />

      <div>
        <.header>
          {gettext("Daily summary email")}
          <:subtitle>
            {gettext("Receive a morning email with today's plans and budget alerts.")}
          </:subtitle>
        </.header>
        <form id="daily-summary-email-form" phx-change="update_daily_summary_email" class="mt-4">
          <.input
            name="daily_summary_email_enabled"
            type="checkbox"
            value="true"
            checked={@daily_summary_email_enabled}
            label={gettext("Send me the daily summary email")}
          />
        </form>
      </div>

      <div class="divider" />

      <div>
        <.header>
          {gettext("API access")}
          <:subtitle>
            {gettext(
              "Personal access tokens let apps you connect read your household's data — read-only, except for creating recipes and planning meals."
            )}
          </:subtitle>
        </.header>

        <div :if={@new_token} class="alert alert-warning mt-4">
          <div>
            <p class="font-semibold">
              {gettext("Copy your token now — you won't be able to see it again.")}
            </p>
            <p class="font-mono text-sm break-all mt-1">{@new_token}</p>
          </div>
        </div>

        <.form
          for={@access_token_form}
          id="access_token_form"
          phx-submit="create_access_token"
          class="mt-4"
        >
          <.input
            field={@access_token_form[:name]}
            type="text"
            label={gettext("Token name")}
            placeholder={gettext("e.g. My budgeting app")}
            required
          />
          <.input
            :if={@current_scope.user.role == :owner}
            field={@access_token_form[:meal_write]}
            type="checkbox"
            label={gettext("Allow recipe and meal-plan changes")}
          />
          <.button variant="primary" phx-disable-with={gettext("Generating...")}>
            {gettext("Generate token")}
          </.button>
        </.form>

        <div class="mt-4">
          <.table id="access-tokens" rows={@access_tokens}>
            <:col :let={token} label={gettext("Name")}>{token.name}</:col>
            <:col :let={token} label={gettext("Scopes")}>{Enum.join(token.scopes, ", ")}</:col>
            <:col :let={token} label={gettext("Created")}>{token.inserted_at}</:col>
            <:col :let={token} label={gettext("Last used")}>
              {token.last_used_at || gettext("Never")}
            </:col>
            <:action :let={token}>
              <.button
                phx-click="revoke_access_token"
                phx-value-id={token.id}
                data-confirm={gettext("Revoke this token?")}
              >
                {gettext("Revoke")}
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
          put_flash(socket, :info, gettext("Email changed successfully."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
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
      |> assign(:email_auth_enabled, "email" in user.auth_providers)
      |> assign(:password_auth_enabled, "email" in user.auth_providers)
      |> assign(:google_calendar_connected, not is_nil(user.google_calendar))
      |> assign(
        :google_calendar_calendars,
        get_in(user.google_calendar || %{}, ["calendars"]) || []
      )
      |> assign(
        :google_calendar_ids,
        get_in(user.google_calendar || %{}, ["calendar_ids"]) || ["primary"]
      )
      |> assign(
        :google_calendar_last_synced_at,
        get_in(user.google_calendar || %{}, ["last_synced_at"])
      )
      |> assign(
        :google_calendar_last_sync_error,
        get_in(user.google_calendar || %{}, ["last_sync_error"])
      )
      |> assign(:daily_summary_email_enabled, user.daily_summary_email_enabled)
      |> assign(
        :access_token_form,
        to_form(%{"name" => "", "meal_write" => false}, as: "access_token")
      )
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

        info = gettext("A link to confirm your email change has been sent to the new address.")
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
    user = socket.assigns.current_scope.user

    if user.role != :owner do
      {:noreply, put_flash(socket, :error, gettext("Only the household owner can send invites."))}
    else
      send_invite(socket, user, email)
    end
  end

  def handle_event("create_access_token", %{"access_token" => token_params}, socket) do
    scope = socket.assigns.current_scope
    name = token_params["name"]

    scopes =
      if token_params["meal_write"] in ["true", true], do: ["read", "meal_write"], else: ["read"]

    if RateLimit.check("access_token:#{scope.user.id}", @access_token_scale, @access_token_limit) ==
         :ok do
      case Households.create_access_token(scope, name, scopes) do
        {:ok, raw_token, _access_token} ->
          {:noreply,
           socket
           |> assign(:new_token, raw_token)
           |> assign(
             :access_token_form,
             to_form(%{"name" => "", "meal_write" => false}, as: "access_token")
           )
           |> assign(:access_tokens, Households.list_access_tokens(scope))}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, gettext("Couldn't create the token — please try again."))}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("Too many tokens created — please wait a while and try again.")
       )}
    end
  end

  def handle_event(
        "update_daily_summary_email",
        %{"daily_summary_email_enabled" => enabled},
        socket
      ) do
    enabled = enabled == "true"
    user = socket.assigns.current_scope.user

    case Households.update_daily_summary_email_preference(user, enabled) do
      {:ok, _user} ->
        {:noreply, assign(socket, :daily_summary_email_enabled, enabled)}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("The daily summary email preference could not be saved.")
         )}
    end
  end

  def handle_event("revoke_access_token", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Households.revoke_access_token(scope, id) do
      {:ok, _access_token} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Token revoked."))
         |> assign(:access_tokens, Households.list_access_tokens(scope))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("That token no longer exists."))}
    end
  end

  def handle_event("sync_google_calendar", _params, socket) do
    user = socket.assigns.current_scope.user

    job =
      SyncWorker.new(%{"user_id" => user.id},
        unique: [fields: [:args, :worker], keys: [:user_id], period: {10, :minutes}]
      )

    case Oban.insert(job) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, gettext("Google Calendar sync started."))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Google Calendar sync could not be started."))}
    end
  end

  def handle_event("refresh_google_calendars", _params, socket) do
    user = socket.assigns.current_scope.user

    case GoogleCalendar.refresh_calendars(user) do
      {:ok, updated_user} ->
        config = updated_user.google_calendar || %{}

        {:noreply,
         socket
         |> assign(:google_calendar_calendars, config["calendars"] || [])
         |> assign(:google_calendar_ids, config["calendar_ids"] || ["primary"])
         |> put_flash(:info, gettext("Google calendars refreshed."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Google calendars could not be loaded."))}
    end
  end

  def handle_event("save_google_calendar_selection", %{"calendar_ids" => calendar_ids}, socket) do
    calendar_ids = Enum.reject(List.wrap(calendar_ids), &(&1 == "false"))
    user = socket.assigns.current_scope.user

    case GoogleCalendar.select_calendars(user, calendar_ids) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> assign(:google_calendar_ids, calendar_ids)
         |> put_flash(:info, gettext("Google calendars saved. Click Sync now to import them."))}

      {:error, :invalid_calendar_selection} ->
        {:noreply, put_flash(socket, :error, gettext("Select at least one valid calendar."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Google calendars could not be saved."))}
    end
  end

  def handle_event("disconnect_google_calendar", _params, socket) do
    scope = socket.assigns.current_scope
    user = scope.user
    {:ok, _count} = Events.delete_google_events(scope)

    case Households.disconnect_google_calendar(user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:google_calendar_connected, false)
         |> put_flash(:info, gettext("Google Calendar disconnected."))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("Google Calendar could not be disconnected."))}
    end
  end

  defp send_invite(socket, user, email) do
    if RateLimit.check("invite:#{user.id}", @invite_scale, @invite_limit) == :ok do
      Households.deliver_household_invite(
        user,
        email,
        &url(~p"/users/register?#{[token: &1]}")
      )

      {:noreply,
       socket
       |> put_flash(:info, gettext("An invite was sent to %{email}.", email: email))
       |> assign(:invite_form, to_form(%{"email" => ""}, as: "invite"))}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("Too many invites sent — please wait a while and try again.")
       )}
    end
  end
end
