defmodule BudgeteerWeb.TransactionLive.Form do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias Budgeteer.Ledger.Transaction

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {@page_title}
        <:subtitle>{gettext("For %{account}", account: @account.name)}</:subtitle>
      </.header>

      <.form for={@form} id="transaction-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:date]} type="date" label={gettext("Date")} />
        <.input
          field={@form[:amount]}
          type="text"
          label={gettext("Amount")}
          placeholder={gettext("e.g. -42.50 for a debit")}
        />
        <.input field={@form[:merchant]} type="text" label={gettext("Merchant")} />
        <.input field={@form[:description]} type="text" label={gettext("Description")} />
        <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />
        <.input
          field={@form[:category_id]}
          type="select"
          label={gettext("Category")}
          prompt={gettext("Uncategorized")}
          options={Enum.map(@categories, &{&1.name, &1.id})}
        />
        <footer>
          <.button phx-disable-with={gettext("Saving...")} variant="primary">
            {gettext("Save Transaction")}
          </.button>
          <.button navigate={return_path(@account, @return_to, @transaction)}>
            {gettext("Cancel")}
          </.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"account_id" => account_id} = params, _session, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, account_id)

    {:ok,
     socket
     |> assign(:account, account)
     |> assign(:categories, Ledger.list_categories(socket.assigns.current_scope))
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    transaction = Ledger.get_transaction!(socket.assigns.current_scope, id)

    transaction = %{
      transaction
      | amount: Budgeteer.Money.to_decimal_string(transaction.amount_cents)
    }

    socket
    |> assign(:page_title, gettext("Edit Transaction"))
    |> assign(:transaction, transaction)
    |> assign(
      :form,
      to_form(Ledger.change_transaction(socket.assigns.current_scope, transaction))
    )
  end

  defp apply_action(socket, :new, _params) do
    transaction = %Transaction{
      household_id: socket.assigns.current_scope.user.household_id,
      account_id: socket.assigns.account.id,
      date: Date.utc_today()
    }

    socket
    |> assign(:page_title, gettext("New Transaction"))
    |> assign(:transaction, transaction)
    |> assign(
      :form,
      to_form(Ledger.change_transaction(socket.assigns.current_scope, transaction))
    )
  end

  @impl true
  def handle_event("validate", %{"transaction" => transaction_params}, socket) do
    changeset =
      Ledger.change_transaction(
        socket.assigns.current_scope,
        socket.assigns.transaction,
        transaction_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"transaction" => transaction_params}, socket) do
    save_transaction(socket, socket.assigns.live_action, transaction_params)
  end

  defp save_transaction(socket, :edit, transaction_params) do
    case Ledger.update_transaction(
           socket.assigns.current_scope,
           socket.assigns.transaction,
           transaction_params
         ) do
      {:ok, transaction} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Transaction updated successfully"))
         |> push_navigate(
           to: return_path(socket.assigns.account, socket.assigns.return_to, transaction)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_transaction(socket, :new, transaction_params) do
    transaction_params = Map.put(transaction_params, "account_id", socket.assigns.account.id)

    case Ledger.create_transaction(socket.assigns.current_scope, transaction_params) do
      {:ok, transaction} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Transaction created successfully"))
         |> push_navigate(
           to: return_path(socket.assigns.account, socket.assigns.return_to, transaction)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(account, "index", _transaction), do: ~p"/accounts/#{account}/transactions"

  defp return_path(account, "show", transaction),
    do: ~p"/accounts/#{account}/transactions/#{transaction}"
end
