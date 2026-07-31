defmodule BudgeteerWeb.AccountLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {@account.name}
        <:actions>
          <.button navigate={~p"/accounts"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/accounts/#{@account}/statements/new"}>
            <.icon name="hero-arrow-up-tray" /> {gettext("Upload statement")}
          </.button>
          <.button navigate={~p"/accounts/#{@account}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> {gettext("Edit account")}
          </.button>
        </:actions>
      </.header>

      <div class="flex gap-4 mb-4">
        <.button navigate={~p"/accounts/#{@account}/transactions"}>
          <.icon name="hero-list-bullet" /> {gettext("Transactions")}
        </.button>
        <.button navigate={~p"/accounts/#{@account}/statements"}>
          <.icon name="hero-document-text" /> {gettext("Statements")}
        </.button>
      </div>

      <.list>
        <:item title={gettext("Name")}>{@account.name}</:item>
        <:item title={gettext("Bank name")}>{@account.bank_name}</:item>
        <:item title={gettext("Currency")}>{@account.currency}</:item>
        <:item title={gettext("Starting balance")}>
          <.money cents={@account.starting_balance_cents} />
        </:item>
        <:item title={gettext("Current balance")}>
          <.money cents={Ledger.current_balance_cents(@account)} />
        </:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Ledger.subscribe_accounts(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Show Account"))
     |> assign(:account, Ledger.get_account!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %Budgeteer.Ledger.Account{id: id} = account},
        %{assigns: %{account: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :account, account)}
  end

  def handle_info(
        {:deleted, %Budgeteer.Ledger.Account{id: id}},
        %{assigns: %{account: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, gettext("The current account was deleted."))
     |> push_navigate(to: ~p"/accounts")}
  end

  def handle_info({type, %Budgeteer.Ledger.Account{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
