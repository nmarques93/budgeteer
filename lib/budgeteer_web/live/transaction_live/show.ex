defmodule BudgeteerWeb.TransactionLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {transaction_heading(@transaction)}
        <:subtitle>{gettext("For %{account}", account: @account.name)}</:subtitle>
        <:actions>
          <.button navigate={~p"/accounts/#{@account}/transactions"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            variant="primary"
            navigate={~p"/accounts/#{@account}/transactions/#{@transaction}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> {gettext("Edit transaction")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title={gettext("Date")}>{@transaction.date}</:item>
        <:item title={gettext("Amount")}><.money cents={@transaction.amount_cents} /></:item>
        <:item title={gettext("Merchant")}>{@transaction.merchant}</:item>
        <:item title={gettext("Description")}>{@transaction.description}</:item>
        <:item title={gettext("Notes")}>{@transaction.notes}</:item>
        <:item title={gettext("Category")}>{@category_name}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"account_id" => account_id, "id" => id}, _session, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, account_id)

    if connected?(socket) do
      Ledger.subscribe_transactions(socket.assigns.current_scope)
    end

    transaction = Ledger.get_transaction!(socket.assigns.current_scope, id)

    category_name =
      case transaction.category_id do
        nil -> gettext("Uncategorized")
        category_id -> Ledger.get_category!(socket.assigns.current_scope, category_id).name
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("Show Transaction"))
     |> assign(:account, account)
     |> assign(:category_name, category_name)
     |> assign(:transaction, transaction)}
  end

  @impl true
  def handle_info(
        {:updated, %Budgeteer.Ledger.Transaction{id: id} = transaction},
        %{assigns: %{transaction: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :transaction, transaction)}
  end

  def handle_info(
        {:deleted, %Budgeteer.Ledger.Transaction{id: id}},
        %{assigns: %{transaction: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, gettext("The current transaction was deleted."))
     |> push_navigate(to: ~p"/accounts/#{socket.assigns.account}/transactions")}
  end

  def handle_info({type, %Budgeteer.Ledger.Transaction{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  defp transaction_heading(%{merchant: merchant}) when merchant not in [nil, ""], do: merchant

  defp transaction_heading(%{description: description}) when description not in [nil, ""],
    do: description

  defp transaction_heading(_transaction), do: gettext("Transaction")
end
