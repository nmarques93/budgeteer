defmodule BudgeteerWeb.UserLive.Registration do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Households
  alias Budgeteer.Households.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <p :if={@invite} class="mb-4">
            You're joining <strong>{@invite.household.name}</strong>.
          </p>

          <.input
            :if={!@invite}
            field={@form[:household_name]}
            type="text"
            label="Household name"
            placeholder="e.g. The Marques Family"
            required
            phx-mounted={JS.focus()}
          />

          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            readonly={!!@invite}
            required
          />

          <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
            Create an account
          </.button>
        </.form>

        <div>
          <div class="divider">or</div>

          <.link href={~p"/auth/google?#{[token: @invite_token]}"} class="btn btn-outline w-full">
            Continue with Google
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: BudgeteerWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(params, _session, socket) do
    invite = resolve_invite(params["token"])

    socket =
      if params["token"] && !invite do
        put_flash(socket, :error, "This invite link is invalid or has expired.")
      else
        socket
      end

    changeset =
      if invite do
        Households.change_invited_user_registration(%User{}, %{"email" => invite.email}, validate_unique: false)
      else
        Households.change_user_registration(%User{}, %{}, validate_unique: false)
      end

    {:ok,
     socket
     |> assign(:invite, invite)
     |> assign(:invite_token, params["token"])
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  defp resolve_invite(nil), do: nil

  defp resolve_invite(token) do
    case Households.get_household_invite(token) do
      {:ok, household, email} -> %{household: household, email: email}
      :error -> nil
    end
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    result =
      case socket.assigns.invite do
        %{household: household} -> Households.register_invited_user(user_params, household)
        nil -> Households.register_user(user_params)
      end

    case result do
      {:ok, user} ->
        {:ok, _} =
          Households.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      case socket.assigns.invite do
        %{} -> Households.change_invited_user_registration(%User{}, user_params, validate_unique: false)
        nil -> Households.change_user_registration(%User{}, user_params, validate_unique: false)
      end

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
