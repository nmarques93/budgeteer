defmodule BudgeteerWeb.StatementLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias Budgeteer.Statements
  alias Budgeteer.Statements.Statement

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Statements for {@account.name}
        <:subtitle>
          <.link navigate={~p"/accounts/#{@account}"}>Back to account</.link>
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/accounts/#{@account}/statements/new"}>
            <.icon name="hero-plus" /> Upload statement
          </.button>
        </:actions>
      </.header>

      <div :if={@processing_filenames != []} class="alert alert-info mb-4">
        <.icon name="hero-arrow-path" class="size-5 shrink-0 motion-safe:animate-spin" />
        <div>
          <p class="font-semibold">
            {ngettext("Processing 1 statement…", "Processing %{count} statements…", length(@processing_filenames))}
          </p>
          <p class="text-sm opacity-80">
            {Enum.join(@processing_filenames, ", ")} — extracting transactions. This can take up to a
            minute for longer documents; the status below updates automatically, no need to refresh.
          </p>
        </div>
      </div>

      <.table id="statements" rows={@streams.statements}>
        <:col :let={{_id, statement}} label="Filename">{statement.filename}</:col>
        <:col :let={{_id, statement}} label="Uploaded">{statement.inserted_at}</:col>
        <:col :let={{_id, statement}} label="Status">
          <span class={["badge", status_class(statement.status)]}>
            <.icon
              :if={statement.status in [:pending, :processing]}
              name="hero-arrow-path"
              class="size-3 motion-safe:animate-spin"
            />
            {statement.status}
          </span>
        </:col>
        <:col :let={{_id, statement}} label="Error">{statement.error_message}</:col>
        <:action :let={{_id, statement}}>
          <.link :if={statement.status == :processed} navigate={~p"/accounts/#{@account}/statements/#{statement}/review"}>
            Review
          </.link>
        </:action>
        <:action :let={{id, statement}}>
          <.link
            phx-click={JS.push("delete", value: %{id: statement.id}) |> hide("##{id}")}
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
      Statements.subscribe_statements(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Statements for #{account.name}")
     |> assign(:account, account)
     |> load_statements()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    statement = Statements.get_statement!(socket.assigns.current_scope, id)
    {:ok, _} = Statements.delete_statement(socket.assigns.current_scope, statement)

    {:noreply, stream_delete(socket, :statements, statement)}
  end

  @impl true
  def handle_info({type, %Statement{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, load_statements(socket)}
  end

  defp load_statements(socket) do
    statements = Statements.list_statements(socket.assigns.current_scope, socket.assigns.account)
    processing_filenames = for s <- statements, s.status in [:pending, :processing], do: s.filename

    socket
    |> assign(:processing_filenames, processing_filenames)
    |> stream(:statements, statements, reset: true)
  end

  defp status_class(:pending), do: "badge-neutral"
  defp status_class(:processing), do: "badge-info"
  defp status_class(:processed), do: "badge-success"
  defp status_class(:failed), do: "badge-error"
end
