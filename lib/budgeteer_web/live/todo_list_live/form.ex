defmodule BudgeteerWeb.TodoListLive.Form do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Todos
  alias Budgeteer.Todos.TodoList

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="todo-list-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <footer>
          <.button phx-disable-with={gettext("Saving...")} variant="primary">
            {gettext("Save list")}
          </.button>
          <.button navigate={return_path(@return_to, @todo_list)}>{gettext("Cancel")}</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, if(params["return_to"] == "show", do: "show", else: "index"))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    todo_list = Todos.get_todo_list!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, gettext("Edit TODO list"))
    |> assign(:todo_list, todo_list)
    |> assign(:form, to_form(Todos.change_todo_list(socket.assigns.current_scope, todo_list)))
  end

  defp apply_action(socket, :new, _params) do
    todo_list = %TodoList{household_id: socket.assigns.current_scope.user.household_id}

    socket
    |> assign(:page_title, gettext("New TODO list"))
    |> assign(:todo_list, todo_list)
    |> assign(:form, to_form(Todos.change_todo_list(socket.assigns.current_scope, todo_list)))
  end

  @impl true
  def handle_event("validate", %{"todo_list" => params}, socket) do
    changeset =
      Todos.change_todo_list(socket.assigns.current_scope, socket.assigns.todo_list, params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"todo_list" => params}, socket) do
    case socket.assigns.live_action do
      :new -> save_new(socket, params)
      :edit -> save_edit(socket, params)
    end
  end

  defp save_new(socket, params) do
    case Todos.create_todo_list(socket.assigns.current_scope, params) do
      {:ok, todo_list} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("TODO list created successfully"))
         |> push_navigate(to: return_path(socket.assigns.return_to, todo_list))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_edit(socket, params) do
    case Todos.update_todo_list(socket.assigns.current_scope, socket.assigns.todo_list, params) do
      {:ok, todo_list} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("TODO list updated successfully"))
         |> push_navigate(to: return_path(socket.assigns.return_to, todo_list))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("show", todo_list), do: ~p"/todos/#{todo_list}"
  defp return_path(_return_to, _todo_list), do: ~p"/todos"
end
