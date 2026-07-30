defmodule BudgeteerWeb.DashboardLive do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Dashboard
      </.header>

      <div class="mt-4">
        <div class="text-sm opacity-70">Total balance</div>
        <div class="text-3xl font-bold"><.money cents={@total_balance_cents} /></div>
        <div class="text-xs opacity-60 mt-1">Last 30 days</div>
        <.sparkline history={@balance_history} />
      </div>

      <h2 class="text-lg font-semibold mt-8">This month by category</h2>
      <.table id="category-totals" rows={@category_totals}>
        <:col :let={row} label="Category">{row.name}</:col>
        <:col :let={row} label="Type">{row.type}</:col>
        <:col :let={row} label="Spent"><.money cents={row.total_cents} /></:col>
        <:col :let={row} label="Budget"><.money cents={row.budget_cents} /></:col>
        <:col :let={row} label="Progress"><.budget_meter row={row} /></:col>
      </.table>

      <h2 class="text-lg font-semibold mt-8">Recent transactions</h2>
      <.table id="recent-transactions" rows={@recent_transactions}>
        <:col :let={transaction} label="Date">{transaction.date}</:col>
        <:col :let={transaction} label="Account">{account_name(@accounts_by_id, transaction.account_id)}</:col>
        <:col :let={transaction} label="Merchant">{transaction.merchant}</:col>
        <:col :let={transaction} label="Amount"><.money cents={transaction.amount_cents} /></:col>
        <:col :let={transaction} label="Category">{category_name(@categories_by_id, transaction.category_id)}</:col>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Ledger.subscribe_accounts(scope)
      Ledger.subscribe_transactions(scope)
      Ledger.subscribe_categories(scope)
    end

    accounts_by_id = Map.new(Ledger.list_accounts(scope), &{&1.id, &1.name})
    categories_by_id = Map.new(Ledger.list_categories(scope), &{&1.id, &1.name})

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:accounts_by_id, accounts_by_id)
     |> assign(:categories_by_id, categories_by_id)
     |> load_data()}
  end

  @impl true
  def handle_info({type, _record}, socket) when type in [:created, :updated, :deleted] do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(:accounts_by_id, Map.new(Ledger.list_accounts(scope), &{&1.id, &1.name}))
     |> assign(:categories_by_id, Map.new(Ledger.list_categories(scope), &{&1.id, &1.name}))
     |> load_data()}
  end

  defp load_data(socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:total_balance_cents, Ledger.total_balance_cents(scope))
    |> assign(:balance_history, Ledger.balance_history(scope))
    |> assign(:category_totals, decimal_totals(Ledger.monthly_category_totals(scope)))
    |> assign(:recent_transactions, Ledger.list_recent_transactions(scope))
  end

  defp decimal_totals(rows) do
    Enum.map(rows, &Map.update!(&1, :total_cents, fn d -> Decimal.to_integer(d) end))
  end

  defp account_name(accounts_by_id, account_id), do: Map.get(accounts_by_id, account_id, "Unknown account")

  defp category_name(_categories_by_id, nil), do: "Uncategorized"
  defp category_name(categories_by_id, category_id), do: Map.get(categories_by_id, category_id, "Uncategorized")

  @doc """
  Renders the household's balance trend as a hairline SVG line chart with a
  faint fill, matching the "Ledger" theme rather than a typical
  charting-library look (no gradients, no drop shadows). Includes a
  crosshair + tooltip on hover/focus — the static line alone shows the
  shape of the trend but not any actual date/balance value.
  """
  attr :history, :list, required: true

  def sparkline(assigns) do
    points = spark_points(assigns.history)
    assigns = assign(assigns, :points, points)

    ~H"""
    <div id="balance-sparkline" phx-hook=".Sparkline" data-points={Jason.encode!(@points.hover)} class="relative mt-2">
      <svg viewBox="0 0 100 32" preserveAspectRatio="none" class="w-full h-10 text-primary" data-sparkline-svg>
        <line x1="0" y1="31.5" x2="100" y2="31.5" class="stroke-base-300" stroke-width="0.5" />
        <polygon :if={@points.line != ""} points={@points.area} fill="currentColor" class="opacity-10" />
        <polyline
          :if={@points.line != ""}
          points={@points.line}
          fill="none"
          stroke="currentColor"
          stroke-width="1"
          vector-effect="non-scaling-stroke"
        />
        <circle :if={@points.last} cx={elem(@points.last, 0)} cy={elem(@points.last, 1)} r="1.5" fill="currentColor" />
        <line
          data-crosshair
          class="hidden stroke-base-content/40"
          x1="0"
          y1="1"
          x2="0"
          y2="31"
          stroke-width="0.5"
          vector-effect="non-scaling-stroke"
        />
      </svg>
      <div
        data-tooltip
        class="hidden absolute -top-9 pointer-events-none text-xs bg-base-100 border border-base-300 rounded px-2 py-1 shadow-sm whitespace-nowrap z-10"
      >
        <span data-tooltip-date class="opacity-60"></span>
        <span data-tooltip-value class="font-mono font-semibold ml-1"></span>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Sparkline">
        export default {
          mounted() {
            this.points = JSON.parse(this.el.dataset.points || "[]")
            this.svg = this.el.querySelector("[data-sparkline-svg]")
            this.crosshair = this.el.querySelector("[data-crosshair]")
            this.tooltip = this.el.querySelector("[data-tooltip]")
            this.tooltipDate = this.el.querySelector("[data-tooltip-date]")
            this.tooltipValue = this.el.querySelector("[data-tooltip-value]")

            this.onMove = (e) => this.handleMove(e)
            this.onLeave = () => this.hideAll()

            this.el.addEventListener("pointermove", this.onMove)
            this.el.addEventListener("pointerleave", this.onLeave)
          },

          updated() {
            this.points = JSON.parse(this.el.dataset.points || "[]")
          },

          destroyed() {
            this.el.removeEventListener("pointermove", this.onMove)
            this.el.removeEventListener("pointerleave", this.onLeave)
          },

          handleMove(e) {
            if (this.points.length === 0) return

            const rect = this.svg.getBoundingClientRect()
            const ratio = Math.min(Math.max((e.clientX - rect.left) / rect.width, 0), 1)
            const index = Math.round(ratio * (this.points.length - 1))
            const point = this.points[index]
            if (!point) return

            this.crosshair.setAttribute("x1", point.x)
            this.crosshair.setAttribute("x2", point.x)
            this.crosshair.classList.remove("hidden")

            this.tooltipDate.textContent = point.date
            this.tooltipValue.textContent = point.value
            this.tooltip.classList.remove("hidden")
            this.tooltip.style.left = `${point.x}%`
            this.tooltip.style.transform = point.x > 70 ? "translateX(-100%)" : "translateX(0)"
          },

          hideAll() {
            this.crosshair.classList.add("hidden")
            this.tooltip.classList.add("hidden")
          }
        }
      </script>
    </div>
    """
  end

  defp spark_points(history) when length(history) < 2, do: %{line: "", area: "", last: nil, hover: []}

  defp spark_points(history) do
    values = Enum.map(history, & &1.balance_cents)
    min_v = Enum.min(values)
    max_v = Enum.max(values)
    span = max(max_v - min_v, 1)
    step = 100 / (length(history) - 1)

    coords =
      history
      |> Enum.with_index()
      |> Enum.map(fn {%{balance_cents: v}, i} ->
        x = Float.round(i * step, 2)
        y = Float.round(2 + (max_v - v) / span * 26, 2)
        {x, y}
      end)

    line = Enum.map_join(coords, " ", fn {x, y} -> "#{x},#{y}" end)
    {first_x, _} = List.first(coords)
    {last_x, _} = List.last(coords)

    hover =
      history
      |> Enum.zip(coords)
      |> Enum.map(fn {%{date: date, balance_cents: cents}, {x, _y}} ->
        %{x: x, date: Calendar.strftime(date, "%b %-d"), value: Budgeteer.Money.format(cents)}
      end)

    %{line: line, area: line <> " #{last_x},30 #{first_x},30", last: List.last(coords), hover: hover}
  end

  @doc """
  Renders a horizontal spend-vs-budget meter for one category row — only
  for expense categories with a budget set, since income categories and
  budgetless categories have nothing to measure progress against.
  """
  attr :row, :map, required: true

  def budget_meter(assigns) do
    ~H"""
    <div :if={meter_visible?(@row)} class="w-32 h-2 rounded-full bg-base-300 overflow-hidden">
      <div class={["h-full rounded-full", meter_color(@row)]} style={"width: #{meter_percent(@row)}%"} />
    </div>
    """
  end

  defp meter_visible?(%{type: :expense, budget_cents: budget}) when is_integer(budget) and budget > 0, do: true
  defp meter_visible?(_row), do: false

  defp meter_percent(%{total_cents: spent, budget_cents: budget}) do
    Float.round(min(abs(spent) / budget, 1.0) * 100, 1)
  end

  defp meter_color(%{total_cents: spent, budget_cents: budget}) do
    if abs(spent) > budget, do: "bg-error", else: "bg-primary"
  end
end
