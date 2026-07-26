defmodule BudgeteerWeb.AccountLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Account {@account.id}
        <:subtitle>This is a account record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/accounts"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/accounts/#{@account}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit account
          </.button>
        </:actions>
      </.header>

      <.link navigate={~p"/accounts/#{@account}/transactions"} class="link">
        View transactions
      </.link>

      <.list>
        <:item title="Name">{@account.name}</:item>
        <:item title="Bank name">{@account.bank_name}</:item>
        <:item title="Currency">{@account.currency}</:item>
        <:item title="Starting balance cents">{@account.starting_balance_cents}</:item>
        <:item title="Current balance">{format_cents(Ledger.current_balance_cents(@account))}</:item>
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
     |> assign(:page_title, "Show Account")
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
     |> put_flash(:error, "The current account was deleted.")
     |> push_navigate(to: ~p"/accounts")}
  end

  def handle_info({type, %Budgeteer.Ledger.Account{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  defp format_cents(cents) do
    "€#{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  end
end
