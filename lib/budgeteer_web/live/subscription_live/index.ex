defmodule BudgeteerWeb.SubscriptionLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias Budgeteer.Subscriptions

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {gettext("Recurring Charges")}
        <:subtitle>{gettext("Automatically detected from your transaction history.")}</:subtitle>
      </.header>

      <p :if={@subscriptions == []} class="text-base-content/60 mt-4">
        {gettext("No recurring charges detected yet.")}
      </p>

      <div :if={@subscriptions != []} class="mt-4">
        <div class="text-sm opacity-70">{gettext("Estimated monthly cost")}</div>
        <div class="text-2xl font-bold"><.money cents={@total_monthly_cents} /></div>
      </div>

      <div :if={@subscriptions != []} class="mt-4">
        <.table id="subscriptions" rows={@subscriptions}>
          <:col :let={sub} label={gettext("Merchant")}>{sub.merchant}</:col>
          <:col :let={sub} label={gettext("Amount")}><.money cents={sub.amount_cents} /></:col>
          <:col :let={sub} label={gettext("Cadence")}>{cadence_label(sub.cadence)}</:col>
          <:col :let={sub} label={gettext("≈ Monthly")}>
            <.money cents={Subscriptions.monthly_equivalent_cents(sub)} />
          </:col>
          <:col :let={sub} label={gettext("Last charged")}>{sub.last_date}</:col>
          <:col :let={sub} label={gettext("Next expected")}>{sub.next_expected_date}</:col>
          <:col :let={sub} label={gettext("Category")}>
            <.category_badge category={Map.get(@categories_by_id, sub.category_id)} />
          </:col>
          <:action :let={sub}>
            <.link
              phx-click={
                JS.push("dismiss",
                  value: %{merchant_key: sub.merchant_key, amount_cents: sub.amount_cents}
                )
              }
              data-confirm={gettext("Not actually a subscription? This will stop showing it.")}
            >
              {gettext("Dismiss")}
            </.link>
          </:action>
        </.table>
      </div>

      <div :if={@dismissed != []} class="mt-8">
        <details>
          <summary class="cursor-pointer text-sm opacity-70">
            {gettext("Dismissed (%{count})", count: length(@dismissed))}
          </summary>
          <ul class="mt-2 space-y-2 text-sm">
            <li :for={dismissed <- @dismissed} class="flex items-center gap-3">
              <span class="opacity-70">{dismissed.merchant_key}</span>
              <.money cents={dismissed.amount_cents} />
              <.link phx-click={JS.push("undismiss", value: %{id: dismissed.id})} class="underline">
                {gettext("Restore")}
              </.link>
            </li>
          </ul>
        </details>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Ledger.subscribe_transactions(scope)
      Subscriptions.subscribe_subscriptions(scope)
    end

    categories = Ledger.list_categories(scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Recurring Charges"))
     |> assign(:categories_by_id, Map.new(categories, &{&1.id, &1}))
     |> load_data()}
  end

  @impl true
  def handle_event(
        "dismiss",
        %{"merchant_key" => merchant_key, "amount_cents" => amount_cents},
        socket
      ) do
    {:ok, _dismissed} =
      Subscriptions.dismiss(
        socket.assigns.current_scope,
        merchant_key,
        normalize_cents(amount_cents)
      )

    {:noreply, load_data(socket)}
  end

  def handle_event("undismiss", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Enum.find(socket.assigns.dismissed, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      dismissed ->
        {:ok, _} = Subscriptions.undismiss(scope, dismissed)
        {:noreply, load_data(socket)}
    end
  end

  @impl true
  def handle_info({type, _record}, socket)
      when type in [:created, :updated, :deleted, :dismissed, :undismissed] do
    {:noreply, load_data(socket)}
  end

  defp load_data(socket) do
    scope = socket.assigns.current_scope
    subscriptions = Subscriptions.list_subscriptions(scope)

    socket
    |> assign(:subscriptions, subscriptions)
    |> assign(:total_monthly_cents, total_monthly_cents(subscriptions))
    |> assign(:dismissed, Subscriptions.list_dismissed(scope))
  end

  defp total_monthly_cents(subscriptions) do
    subscriptions |> Enum.map(&Subscriptions.monthly_equivalent_cents/1) |> Enum.sum()
  end

  defp normalize_cents(cents) when is_integer(cents), do: cents
  defp normalize_cents(cents) when is_binary(cents), do: String.to_integer(cents)

  defp cadence_label(:weekly), do: gettext("Weekly")
  defp cadence_label(:biweekly), do: gettext("Every 2 weeks")
  defp cadence_label(:monthly), do: gettext("Monthly")
  defp cadence_label(:quarterly), do: gettext("Quarterly")
  defp cadence_label(:yearly), do: gettext("Yearly")
end
