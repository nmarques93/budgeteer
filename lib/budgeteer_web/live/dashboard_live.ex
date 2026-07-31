defmodule BudgeteerWeb.DashboardLive do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias Budgeteer.Subscriptions

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

      <div
        :if={@subscription_count > 0}
        class="mt-8 rounded border border-base-300 p-4 flex items-center justify-between gap-4"
      >
        <div>
          <div class="text-sm opacity-70">Recurring charges detected</div>
          <div class="text-xl font-bold">
            {@subscription_count} · <.money cents={@subscription_monthly_cents} /> / mo
          </div>
        </div>
        <.link navigate={~p"/subscriptions"} class="btn btn-sm btn-outline shrink-0">View all</.link>
      </div>

      <h2 class="text-lg font-semibold mt-8">This month by category</h2>
      <.category_breakdown_chart breakdown={@category_breakdown} />
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
        <:col :let={transaction} label="Account">
          {account_name(@accounts_by_id, transaction.account_id)}
        </:col>
        <:col :let={transaction} label="Merchant">{transaction.merchant}</:col>
        <:col :let={transaction} label="Amount"><.money cents={transaction.amount_cents} /></:col>
        <:col :let={transaction} label="Category">
          {category_name(@categories_by_id, transaction.category_id)}
        </:col>
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
      Subscriptions.subscribe_subscriptions(scope)
    end

    categories = Ledger.list_categories(scope)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:accounts_by_id, Map.new(Ledger.list_accounts(scope), &{&1.id, &1.name}))
     |> assign(:categories_by_id, Map.new(categories, &{&1.id, &1.name}))
     |> assign(:categories, categories)
     |> load_data()}
  end

  @impl true
  def handle_info({type, _record}, socket)
      when type in [:created, :updated, :deleted, :dismissed, :undismissed] do
    scope = socket.assigns.current_scope
    categories = Ledger.list_categories(scope)

    {:noreply,
     socket
     |> assign(:accounts_by_id, Map.new(Ledger.list_accounts(scope), &{&1.id, &1.name}))
     |> assign(:categories_by_id, Map.new(categories, &{&1.id, &1.name}))
     |> assign(:categories, categories)
     |> load_data()}
  end

  defp load_data(socket) do
    scope = socket.assigns.current_scope
    category_totals = decimal_totals(Ledger.monthly_category_totals(scope))
    subscriptions = Subscriptions.list_subscriptions(scope)

    socket
    |> assign(:total_balance_cents, Ledger.total_balance_cents(scope))
    |> assign(:balance_history, Ledger.balance_history(scope))
    |> assign(:category_totals, category_totals)
    |> assign(:category_breakdown, category_breakdown(socket.assigns.categories, category_totals))
    |> assign(:recent_transactions, Ledger.list_recent_transactions(scope))
    |> assign(:subscription_count, length(subscriptions))
    |> assign(
      :subscription_monthly_cents,
      Enum.sum(Enum.map(subscriptions, &Subscriptions.monthly_equivalent_cents/1))
    )
  end

  # Stable color-slot assignment: categories are given a fixed slot by
  # alphabetical order among the household's own expense categories, not by
  # this month's spend rank — otherwise the same category could repaint a
  # different color from month to month as spending patterns shift (see
  # the dataviz skill's "color follows the entity, never its rank" rule).
  # Categories beyond the 8-slot cap fold into a single gray "Other"
  # segment rather than generating a 9th hue.
  defp category_breakdown(categories, category_totals) do
    slot_by_name =
      categories
      |> Enum.filter(&(&1.type == :expense))
      |> Enum.map(& &1.name)
      |> Enum.sort()
      |> Enum.with_index(1)
      |> Map.new()

    spend_by_name =
      category_totals
      |> Enum.filter(&(&1.type == :expense and &1.total_cents < 0))
      |> Map.new(&{&1.name, abs(&1.total_cents)})

    total_cents = spend_by_name |> Map.values() |> Enum.sum()

    if total_cents == 0 do
      []
    else
      {main, other} =
        spend_by_name
        |> Enum.map(fn {name, cents} -> {name, cents, Map.fetch!(slot_by_name, name)} end)
        |> Enum.split_with(fn {_name, _cents, slot} -> slot <= 8 end)

      main_segments =
        main
        |> Enum.sort_by(fn {_name, _cents, slot} -> slot end)
        |> Enum.map(fn {name, cents, slot} ->
          breakdown_segment(name, cents, total_cents, "var(--series-#{slot})")
        end)

      case Enum.sum(Enum.map(other, fn {_name, cents, _slot} -> cents end)) do
        0 ->
          main_segments

        other_cents ->
          main_segments ++
            [breakdown_segment("Other", other_cents, total_cents, "var(--series-other)")]
      end
    end
  end

  defp breakdown_segment(name, cents, total_cents, color) do
    %{
      name: name,
      formatted: Budgeteer.Money.format(-cents),
      percent: Float.round(cents / total_cents * 100, 1),
      color: color
    }
  end

  defp decimal_totals(rows) do
    Enum.map(rows, &Map.update!(&1, :total_cents, fn d -> Decimal.to_integer(d) end))
  end

  defp account_name(accounts_by_id, account_id),
    do: Map.get(accounts_by_id, account_id, "Unknown account")

  defp category_name(_categories_by_id, nil), do: "Uncategorized"

  defp category_name(categories_by_id, category_id),
    do: Map.get(categories_by_id, category_id, "Uncategorized")

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
    <div
      id="balance-sparkline"
      phx-hook=".Sparkline"
      data-points={Jason.encode!(@points.hover)}
      class="relative mt-2"
    >
      <svg
        viewBox="0 0 100 32"
        preserveAspectRatio="none"
        class="w-full h-10 text-primary"
        data-sparkline-svg
      >
        <line x1="0" y1="31.5" x2="100" y2="31.5" class="stroke-base-300" stroke-width="0.5" />
        <polygon
          :if={@points.line != ""}
          points={@points.area}
          fill="currentColor"
          class="opacity-10"
        />
        <polyline
          :if={@points.line != ""}
          points={@points.line}
          fill="none"
          stroke="currentColor"
          stroke-width="1"
          vector-effect="non-scaling-stroke"
        />
        <circle
          :if={@points.last}
          cx={elem(@points.last, 0)}
          cy={elem(@points.last, 1)}
          r="1.5"
          fill="currentColor"
        />
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

  defp spark_points(history) when length(history) < 2,
    do: %{line: "", area: "", last: nil, hover: []}

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

    %{
      line: line,
      area: line <> " #{last_x},30 #{first_x},30",
      last: List.last(coords),
      hover: hover
    }
  end

  @doc """
  Renders this month's expense spend as a single horizontal stacked bar —
  one segment per category, proportional to its share of total spend.
  Complements the per-row budget meters in the table below: those answer
  "how does each category compare to its own budget," this answers "where
  did the money actually go, relative to everything else." Uses the
  dataviz skill's validated categorical palette (`app.css`'s
  `--series-*` custom properties) with a fixed, alphabetically-assigned
  slot per category — never colored by this month's spend rank, so a
  category's color stays stable across months.
  """
  attr :breakdown, :list, required: true

  def category_breakdown_chart(assigns) do
    ~H"""
    <div
      :if={@breakdown != []}
      id="category-breakdown"
      phx-hook=".CategoryBreakdown"
      class="relative mt-2 mb-6"
    >
      <div data-bar class="flex gap-0.5 h-4 rounded-full overflow-hidden">
        <div
          :for={segment <- @breakdown}
          class="h-full transition-filter hover:brightness-110 focus:brightness-110 outline-none"
          style={"width: #{segment.percent}%; background-color: #{segment.color}"}
          tabindex="0"
          data-name={segment.name}
          data-value={segment.formatted}
          data-percent={segment.percent}
        />
      </div>
      <div
        data-tooltip
        class="hidden absolute -top-9 pointer-events-none text-xs bg-base-100 border border-base-300 rounded px-2 py-1 shadow-sm whitespace-nowrap z-10"
      >
        <span data-tooltip-name class="opacity-60"></span>
        <span data-tooltip-value class="font-mono font-semibold ml-1"></span>
      </div>
      <div class="flex flex-wrap gap-x-4 gap-y-1 mt-2 text-xs">
        <div :for={segment <- @breakdown} class="flex items-center gap-1.5">
          <span
            class="inline-block size-2 rounded-full shrink-0"
            style={"background-color: #{segment.color}"}
          ></span>
          <span class="opacity-70">{segment.name}</span>
          <span class="font-mono">{segment.formatted}</span>
        </div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CategoryBreakdown">
        export default {
          mounted() {
            this.tooltip = this.el.querySelector("[data-tooltip]")
            this.tooltipName = this.el.querySelector("[data-tooltip-name]")
            this.tooltipValue = this.el.querySelector("[data-tooltip-value]")
            this.bar = this.el.querySelector("[data-bar]")

            this.onOver = (e) => this.handleOver(e)
            this.onOut = (e) => this.handleOut(e)

            this.el.addEventListener("pointerover", this.onOver)
            this.el.addEventListener("pointerout", this.onOut)
            this.el.addEventListener("focusin", this.onOver)
            this.el.addEventListener("focusout", this.onOut)
          },

          destroyed() {
            this.el.removeEventListener("pointerover", this.onOver)
            this.el.removeEventListener("pointerout", this.onOut)
            this.el.removeEventListener("focusin", this.onOver)
            this.el.removeEventListener("focusout", this.onOut)
          },

          handleOver(e) {
            const segment = e.target.closest("[data-name]")
            if (!segment) return

            this.tooltipName.textContent = segment.dataset.name
            this.tooltipValue.textContent = segment.dataset.value
            this.tooltip.classList.remove("hidden")

            const barRect = this.bar.getBoundingClientRect()
            const segRect = segment.getBoundingClientRect()
            const center = ((segRect.left + segRect.width / 2 - barRect.left) / barRect.width) * 100

            this.tooltip.style.left = `${center}%`
            this.tooltip.style.transform =
              center > 70 ? "translateX(-100%)" : center < 30 ? "translateX(0)" : "translateX(-50%)"
          },

          handleOut(e) {
            if (e.target.closest("[data-name]")) this.tooltip.classList.add("hidden")
          }
        }
      </script>
    </div>
    """
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
      <div
        class={["h-full rounded-full", meter_color(@row)]}
        style={"width: #{meter_percent(@row)}%"}
      />
    </div>
    """
  end

  defp meter_visible?(%{type: :expense, budget_cents: budget})
       when is_integer(budget) and budget > 0, do: true

  defp meter_visible?(_row), do: false

  defp meter_percent(%{total_cents: spent, budget_cents: budget}) do
    Float.round(min(abs(spent) / budget, 1.0) * 100, 1)
  end

  defp meter_color(%{total_cents: spent, budget_cents: budget}) do
    if abs(spent) > budget, do: "bg-error", else: "bg-primary"
  end
end
