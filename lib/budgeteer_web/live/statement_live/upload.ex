defmodule BudgeteerWeb.StatementLive.Upload do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Upload statement
        <:subtitle>For {@account.name}</:subtitle>
      </.header>

      <.form for={%{}} action={~p"/accounts/#{@account}/statements"} method="post" multipart>
        <div class="rounded-box border border-base-300 p-6">
          <input type="file" name="statement[file]" accept=".pdf,.jpg,.jpeg,.png" required class="w-full" />
          <p class="text-sm opacity-70 mt-2">PDF, JPG, or PNG — up to 15 MB.</p>
        </div>

        <footer class="mt-4">
          <.button phx-disable-with="Uploading..." variant="primary">Upload</.button>
          <.button navigate={~p"/accounts/#{@account}/statements"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"account_id" => account_id}, _session, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, account_id)

    {:ok,
     socket
     |> assign(:page_title, "Upload Statement")
     |> assign(:account, account)}
  end
end
