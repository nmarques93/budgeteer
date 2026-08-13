defmodule BudgeteerWeb.TransactionLive.Search do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias BudgeteerWeb.TransactionLive.FilterForm

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {gettext("Search Transactions")}
        <:subtitle>{gettext("Search across every account in the household.")}</:subtitle>
        <:actions>
          <.button href={~p"/transactions/export?#{FilterForm.export_query(@filter_params)}"}>
            <.icon name="hero-arrow-down-tray" /> {gettext("Export CSV")}
          </.button>
        </:actions>
      </.header>

      <FilterForm.filter_form filters={@filter_params} categories={@categories} accounts={@accounts} />

      <p :if={@result_count == 0} class="text-base-content/60">
        {gettext("No transactions match these filters.")}
      </p>

      <div :if={@result_count > 0} class="hidden md:block">
        <.table
          id="transactions"
          rows={@streams.transactions}
          row_click={
            fn {_id, transaction} ->
              JS.navigate(~p"/accounts/#{transaction.account_id}/transactions/#{transaction}")
            end
          }
        >
          <:col :let={{_id, transaction}} label={gettext("Date")}>{transaction.date}</:col>
          <:col :let={{_id, transaction}} label={gettext("Account")}>
            {account_name(@accounts_by_id, transaction.account_id)}
          </:col>
          <:col :let={{_id, transaction}} label={gettext("Amount")}>
            <.money cents={transaction.amount_cents} />
          </:col>
          <:col :let={{_id, transaction}} label={gettext("Merchant")}>{transaction.merchant}</:col>
          <:col :let={{_id, transaction}} label={gettext("Description")}>
            {transaction.description}
          </:col>
          <:col :let={{_id, transaction}} label={gettext("Category")}>
            <.category_badge category={Map.get(@categories_by_id, transaction.category_id)} />
          </:col>
        </.table>
      </div>

      <div :if={@result_count > 0} id="transactions-mobile" class="space-y-2 md:hidden">
        <article
          :for={{id, transaction} <- @streams.transactions}
          id={"mobile-#{id}"}
          class="rounded border border-base-300 p-3"
        >
          <.link
            navigate={~p"/accounts/#{transaction.account_id}/transactions/#{transaction}"}
            class="block"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="font-semibold truncate">
                  {transaction.merchant || transaction.description}
                </p>
                <p class="text-xs opacity-60">
                  {transaction.date} · {account_name(@accounts_by_id, transaction.account_id)}
                </p>
              </div>
              <.money cents={transaction.amount_cents} />
            </div>
            <div class="mt-2">
              <.category_badge category={Map.get(@categories_by_id, transaction.category_id)} />
            </div>
          </.link>
        </article>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Ledger.subscribe_transactions(scope)
    end

    accounts = Ledger.list_accounts(scope)
    categories = Ledger.list_categories(scope)
    filter_params = FilterForm.normalize_params(%{})
    results = Ledger.search_transactions(scope, FilterForm.to_filters(filter_params))

    {:ok,
     socket
     |> assign(:page_title, gettext("Search Transactions"))
     |> assign(:accounts, accounts)
     |> assign(:accounts_by_id, Map.new(accounts, &{&1.id, &1.name}))
     |> assign(:categories, categories)
     |> assign(:categories_by_id, Map.new(categories, &{&1.id, &1}))
     |> assign(:filter_params, filter_params)
     |> assign(:result_count, length(results))
     |> stream(:transactions, results)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filter_params = FilterForm.normalize_params(params)

    results =
      Ledger.search_transactions(
        socket.assigns.current_scope,
        FilterForm.to_filters(filter_params)
      )

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
      Ledger.search_transactions(
        socket.assigns.current_scope,
        FilterForm.to_filters(socket.assigns.filter_params)
      )

    {:noreply,
     socket
     |> assign(:result_count, length(results))
     |> stream(:transactions, results, reset: true)}
  end

  defp account_name(accounts_by_id, account_id), do: Map.get(accounts_by_id, account_id, "—")
end
