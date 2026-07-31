defmodule BudgeteerWeb.UserLive.Login do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Households
  alias Budgeteer.RateLimit

  # Keyed by the target email, not the requester — this guards against
  # spamming someone else's inbox with login-link emails, which an IP-based
  # limit wouldn't catch (a single requester could still target many
  # emails from one IP, but that's a smaller nuisance than one email
  # getting flooded).
  @magic_link_scale :timer.minutes(15)
  @magic_link_limit 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>{gettext("Log in")}</p>
            <:subtitle>
              <%= if @current_scope do %>
                {gettext("You need to reauthenticate to perform sensitive actions on your account.")}
              <% else %>
                {gettext("Don't have an account?")} <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >{gettext("Sign up")}</.link> {gettext("for an account now.")}
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>{gettext("Emails aren't actually being sent in this environment.")}</p>
            <p>
              {gettext("View them at")} <.link href="/dev/mailbox" class="underline">{gettext("the mailbox page")}</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            {gettext("Log in with email")} <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">{gettext("or")}</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <input :if={@return_to} type="hidden" name="return_to" value={@return_to} />
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("Password")}
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            {gettext("Log in and stay logged in")} <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            {gettext("Log in only this time")}
          </.button>
        </.form>

        <div>
          <div class="divider">{gettext("or")}</div>

          <.link href={~p"/auth/google?#{[return_to: @return_to]}"} class="btn btn-outline w-full">
            {gettext("Continue with Google")}
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       form: form,
       trigger_submit: false,
       return_to: safe_return_to(params["return_to"])
     )}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if RateLimit.check("magic_link:#{email}", @magic_link_scale, @magic_link_limit) == :ok do
      if user = Households.get_user_by_email(email) do
        Households.deliver_login_instructions(
          user,
          &url(~p"/users/log-in/#{&1}?#{[return_to: socket.assigns.return_to]}")
        )
      end
    end

    info =
      gettext("If your email is in our system, you will receive instructions for logging in shortly.")

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp safe_return_to("/" <> _ = path) do
    if String.starts_with?(path, "//"), do: nil, else: path
  end

  defp safe_return_to(_), do: nil

  defp local_mail_adapter? do
    Application.get_env(:budgeteer, Budgeteer.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
