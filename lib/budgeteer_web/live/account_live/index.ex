defmodule BudgeteerWeb.AccountLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {gettext("Listing Accounts")}
        <:actions>
          <.button variant="primary" navigate={~p"/accounts/new"}>
            <.icon name="hero-plus" /> {gettext("New Account")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="accounts"
        rows={@streams.accounts}
        row_click={fn {_id, account} -> JS.navigate(~p"/accounts/#{account}") end}
      >
        <:col :let={{_id, account}} label={gettext("Name")}>{account.name}</:col>
        <:col :let={{_id, account}} label={gettext("Bank name")}>{account.bank_name}</:col>
        <:col :let={{_id, account}} label={gettext("Currency")}>{account.currency}</:col>
        <:col :let={{_id, account}} label={gettext("Balance")}>
          <.money cents={Ledger.current_balance_cents(account)} />
        </:col>
        <:action :let={{_id, account}}>
          <div class="sr-only">
            <.link navigate={~p"/accounts/#{account}"}>{gettext("Show")}</.link>
          </div>
          <.link navigate={~p"/accounts/#{account}/statements"}>{gettext("Statements")}</.link>
        </:action>
        <:action :let={{_id, account}}>
          <.link navigate={~p"/accounts/#{account}/edit"}>{gettext("Edit")}</.link>
        </:action>
        <:action :let={{id, account}}>
          <.link
            :if={@current_scope.user.role == :owner}
            phx-click={JS.push("delete", value: %{id: account.id}) |> hide("##{id}")}
            data-confirm={gettext("Are you sure?")}
          >
            {gettext("Delete")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Ledger.subscribe_accounts(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Listing Accounts"))
     |> stream(:accounts, list_accounts(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, id)

    case Ledger.delete_account(socket.assigns.current_scope, account) do
      {:ok, _} ->
        {:noreply, stream_delete(socket, :accounts, account)}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, gettext("Only the household owner can delete accounts."))}
    end
  end

  @impl true
  def handle_info({type, %Budgeteer.Ledger.Account{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :accounts, list_accounts(socket.assigns.current_scope), reset: true)}
  end

  defp list_accounts(current_scope) do
    Ledger.list_accounts(current_scope)
  end
end
