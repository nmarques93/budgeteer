defmodule BudgeteerWeb.TodoListLive.Index do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Todos

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {if @show_archived, do: gettext("Archived TODO lists"), else: gettext("TODO lists")}
        <:actions>
          <.button navigate={~p"/todos?#{[archived: !@show_archived]}"}>
            {if @show_archived, do: gettext("Show active"), else: gettext("Show archived")}
          </.button>
          <.button variant="primary" navigate={~p"/todos/new"}>
            <.icon name="hero-plus" /> {gettext("New list")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="todo-lists"
        rows={@streams.todo_lists}
        row_click={fn {_id, todo_list} -> JS.navigate(~p"/todos/#{todo_list}") end}
      >
        <:col :let={{_id, todo_list}} label={gettext("Name")}>{todo_list.name}</:col>
        <:action :let={{_id, todo_list}}>
          <.link :if={!@show_archived} phx-click={JS.push("archive", value: %{id: todo_list.id})}>
            {gettext("Archive")}
          </.link>
          <.link :if={@show_archived} phx-click={JS.push("unarchive", value: %{id: todo_list.id})}>
            {gettext("Unarchive")}
          </.link>
        </:action>
        <:action :let={{id, todo_list}}>
          <.link navigate={~p"/todos/#{todo_list}/edit?return_to=show"}>{gettext("Edit")}</.link>
          <.link
            :if={@current_scope.user.role == :owner}
            phx-click={JS.push("delete", value: %{id: todo_list.id}) |> hide("##{id}")}
            data-confirm={gettext("Delete this TODO list and all its items?")}
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
    if connected?(socket), do: Todos.subscribe_todo_lists(socket.assigns.current_scope)
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    show_archived = params["archived"] == "true"

    {:noreply,
     socket
     |> assign(:page_title, gettext("TODO lists"))
     |> assign(:show_archived, show_archived)
     |> stream(:todo_lists, list_lists(socket.assigns.current_scope, show_archived), reset: true)}
  end

  @impl true
  def handle_event(action, %{"id" => id}, socket)
      when action in ["archive", "unarchive", "delete"] do
    todo_list = Todos.get_todo_list!(socket.assigns.current_scope, id)

    result =
      case action do
        "archive" -> Todos.archive_todo_list(socket.assigns.current_scope, todo_list)
        "unarchive" -> Todos.unarchive_todo_list(socket.assigns.current_scope, todo_list)
        "delete" -> Todos.delete_todo_list(socket.assigns.current_scope, todo_list)
      end

    case result do
      {:ok, _} ->
        {:noreply, stream_delete(socket, :todo_lists, todo_list)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Only the household owner can do that."))}
    end
  end

  @impl true
  def handle_info({type, %Budgeteer.Todos.TodoList{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(
       socket,
       :todo_lists,
       list_lists(socket.assigns.current_scope, socket.assigns.show_archived),
       reset: true
     )}
  end

  defp list_lists(scope, archived?), do: Todos.list_todo_lists(scope, archived: archived?)
end
