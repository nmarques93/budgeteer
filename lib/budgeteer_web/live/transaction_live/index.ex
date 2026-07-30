defmodule BudgeteerWeb.TransactionLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias BudgeteerWeb.TransactionLive.FilterForm

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Transactions for {@account.name}
        <:subtitle>
          <.link navigate={~p"/accounts/#{@account}"}>Back to account</.link>
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/accounts/#{@account}/transactions/new"}>
            <.icon name="hero-plus" /> New Transaction
          </.button>
        </:actions>
      </.header>

      <FilterForm.filter_form filters={@filter_params} categories={@categories} />

      <p :if={@result_count == 0} class="text-base-content/60">
        No transactions match these filters.
      </p>

      <.table
        :if={@result_count > 0}
        id="transactions"
        rows={@streams.transactions}
        row_click={
          fn {_id, transaction} ->
            JS.navigate(~p"/accounts/#{@account}/transactions/#{transaction}")
          end
        }
      >
        <:col :let={{_id, transaction}} label="Date">{transaction.date}</:col>
        <:col :let={{_id, transaction}} label="Amount">
          <.money cents={transaction.amount_cents} />
        </:col>
        <:col :let={{_id, transaction}} label="Merchant">{transaction.merchant}</:col>
        <:col :let={{_id, transaction}} label="Description">{transaction.description}</:col>
        <:col :let={{_id, transaction}} label="Notes">{transaction.notes}</:col>
        <:col :let={{_id, transaction}} label="Category">
          {category_name(@categories_by_id, transaction.category_id)}
        </:col>
        <:action :let={{_id, transaction}}>
          <div class="sr-only">
            <.link navigate={~p"/accounts/#{@account}/transactions/#{transaction}"}>Show</.link>
          </div>
          <.link navigate={~p"/accounts/#{@account}/transactions/#{transaction}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, transaction}}>
          <.link
            phx-click={JS.push("delete", value: %{id: transaction.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"account_id" => account_id}, _session, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, account_id)

    if connected?(socket) do
      Ledger.subscribe_transactions(socket.assigns.current_scope)
    end

    categories = Ledger.list_categories(socket.assigns.current_scope)
    categories_by_id = Map.new(categories, &{&1.id, &1.name})
    filter_params = FilterForm.normalize_params(%{})
    results = search(socket.assigns.current_scope, account, filter_params)

    {:ok,
     socket
     |> assign(:page_title, "Transactions for #{account.name}")
     |> assign(:account, account)
     |> assign(:categories, categories)
     |> assign(:categories_by_id, categories_by_id)
     |> assign(:filter_params, filter_params)
     |> assign(:result_count, length(results))
     |> stream(:transactions, results)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    transaction = Ledger.get_transaction!(socket.assigns.current_scope, id)
    {:ok, _} = Ledger.delete_transaction(socket.assigns.current_scope, transaction)

    {:noreply, stream_delete(socket, :transactions, transaction)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filter_params = FilterForm.normalize_params(params)
    results = search(socket.assigns.current_scope, socket.assigns.account, filter_params)

    {:noreply,
     socket
     |> assign(:filter_params, filter_params)
     |> assign(:result_count, length(results))
     |> stream(:transactions, results, reset: true)}
  end

  @impl true
  def handle_info({type, %Budgeteer.Ledger.Transaction{}}, socket)
      when type in [:created, :updated, :deleted] do
    results =
      search(socket.assigns.current_scope, socket.assigns.account, socket.assigns.filter_params)

    {:noreply,
     socket
     |> assign(:result_count, length(results))
     |> stream(:transactions, results, reset: true)}
  end

  defp search(scope, account, filter_params) do
    filters = filter_params |> FilterForm.to_filters() |> Map.put(:account_id, account.id)
    Ledger.search_transactions(scope, filters)
  end

  defp category_name(_categories_by_id, nil), do: "Uncategorized"

  defp category_name(categories_by_id, category_id),
    do: Map.get(categories_by_id, category_id, "Uncategorized")
end
