defmodule BudgeteerWeb.AccountLive.Form do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias Budgeteer.Ledger.Account

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage account records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="account-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:bank_name]} type="text" label="Bank name" />
        <.input field={@form[:currency]} type="text" label="Currency" />
        <.input field={@form[:starting_balance]} type="text" label="Starting balance" placeholder="e.g. 1500.00" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Account</.button>
          <.button navigate={return_path(@current_scope, @return_to, @account)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    account = Ledger.get_account!(socket.assigns.current_scope, id)
    account = %{account | starting_balance: Budgeteer.Money.to_decimal_string(account.starting_balance_cents)}

    socket
    |> assign(:page_title, "Edit Account")
    |> assign(:account, account)
    |> assign(:form, to_form(Ledger.change_account(socket.assigns.current_scope, account)))
  end

  defp apply_action(socket, :new, _params) do
    account = %Account{
      household_id: socket.assigns.current_scope.user.household_id,
      currency: "EUR",
      starting_balance: "0.00"
    }

    socket
    |> assign(:page_title, "New Account")
    |> assign(:account, account)
    |> assign(:form, to_form(Ledger.change_account(socket.assigns.current_scope, account)))
  end

  @impl true
  def handle_event("validate", %{"account" => account_params}, socket) do
    changeset = Ledger.change_account(socket.assigns.current_scope, socket.assigns.account, account_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"account" => account_params}, socket) do
    save_account(socket, socket.assigns.live_action, account_params)
  end

  defp save_account(socket, :edit, account_params) do
    case Ledger.update_account(socket.assigns.current_scope, socket.assigns.account, account_params) do
      {:ok, account} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, account)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_account(socket, :new, account_params) do
    case Ledger.create_account(socket.assigns.current_scope, account_params) do
      {:ok, account} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, account)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _account), do: ~p"/accounts"
  defp return_path(_scope, "show", account), do: ~p"/accounts/#{account}"
end
