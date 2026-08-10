defmodule BudgeteerWeb.TodoListLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Todos
  alias Budgeteer.Todos.TodoItem

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {@todo_list.name}
        <:subtitle><.link navigate={~p"/todos"}>{gettext("Back to TODO lists")}</.link></:subtitle>
        <:actions>
          <.button navigate={~p"/todos/#{@todo_list}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> {gettext("Rename")}
          </.button>
        </:actions>
      </.header>

      <.form
        for={@item_form}
        id="todo-item-form"
        phx-submit="add_item"
        class="grid grid-cols-1 sm:grid-cols-[minmax(0,1fr)_auto] gap-2 items-end mt-4"
      >
        <.input
          field={@item_form[:title]}
          type="text"
          label={gettext("Task")}
          placeholder={gettext("e.g. Book dentist appointment")}
        />
        <.button phx-disable-with={gettext("Adding...")} variant="primary">
          <.icon name="hero-plus" /> {gettext("Add task")}
        </.button>
      </.form>

      <div id="todo-items" phx-update="stream" class="mt-6 space-y-2">
        <div id="todo-items-empty" class="hidden only:block text-sm opacity-70">
          {gettext("No tasks yet.")}
        </div>
        <div
          :for={{id, item} <- @streams.todo_items}
          id={id}
          class="rounded border border-base-300 p-3"
        >
          <%= if @editing_item_id == item.id do %>
            <.form
              for={@edit_form}
              id={"todo-item-edit-#{item.id}"}
              phx-submit="save_item"
              class="grid grid-cols-1 gap-2"
            >
              <.input field={@edit_form[:title]} type="text" label={gettext("Task")} />
              <.input field={@edit_form[:notes]} type="textarea" label={gettext("Notes")} />
              <.input field={@edit_form[:due_date]} type="date" label={gettext("Due date")} />
              <div class="flex flex-wrap gap-2">
                <.button variant="primary" phx-disable-with={gettext("Saving...")}>{gettext("Save")}</.button>
                <.button type="button" phx-click="cancel_edit">{gettext("Cancel")}</.button>
              </div>
            </.form>
          <% else %>
            <div class="flex items-start gap-3">
              <input
                type="checkbox"
                class="checkbox checkbox-sm mt-1"
                checked={item.completed}
                phx-click="toggle_item"
                phx-value-id={item.id}
                aria-label={gettext("Mark task complete")}
              />
              <div class="min-w-0 flex-1">
                <p class={["font-medium break-words", item.completed && "line-through opacity-60"]}>
                  {item.title}
                </p>
                <p :if={item.notes} class="text-sm opacity-70 whitespace-pre-wrap break-words">
                  {item.notes}
                </p>
                <p :if={item.due_date} class="text-xs opacity-60 mt-1">
                  {gettext("Due %{date}", date: item.due_date)}
                </p>
              </div>
              <div class="flex flex-wrap gap-1 shrink-0">
                <.button
                  type="button"
                  class="btn-sm"
                  phx-click="move_item"
                  phx-value-id={item.id}
                  phx-value-direction="up"
                  aria-label={gettext("Move up")}
                >
                  <.icon name="hero-chevron-up" />
                </.button>
                <.button
                  type="button"
                  class="btn-sm"
                  phx-click="move_item"
                  phx-value-id={item.id}
                  phx-value-direction="down"
                  aria-label={gettext("Move down")}
                >
                  <.icon name="hero-chevron-down" />
                </.button>
                <.button
                  type="button"
                  class="btn-sm"
                  phx-click="edit_item"
                  phx-value-id={item.id}
                  aria-label={gettext("Edit task")}
                >
                  <.icon name="hero-pencil-square" />
                </.button>
                <.button
                  type="button"
                  class="btn-sm text-error"
                  phx-click="delete_item"
                  phx-value-id={item.id}
                  data-confirm={gettext("Delete this task?")}
                  aria-label={gettext("Delete task")}
                >
                  <.icon name="hero-trash" />
                </.button>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    todo_list = Todos.get_todo_list!(socket.assigns.current_scope, id)

    if connected?(socket), do: Todos.subscribe_items(socket.assigns.current_scope, todo_list)

    {:ok,
     socket
     |> assign(:page_title, todo_list.name)
     |> assign(:todo_list, todo_list)
     |> assign(:item_form, item_form(socket.assigns.current_scope))
     |> assign(:edit_form, nil)
     |> assign(:editing_item_id, nil)
     |> stream(:todo_items, Todos.list_items(socket.assigns.current_scope, todo_list))}
  end

  @impl true
  def handle_event("add_item", %{"todo_item" => params}, socket) do
    case Todos.create_item(socket.assigns.current_scope, socket.assigns.todo_list, params) do
      {:ok, item} ->
        {:noreply,
         socket
         |> stream_insert(:todo_items, item)
         |> assign(:item_form, item_form(socket.assigns.current_scope))}

      {:error, changeset} ->
        {:noreply, assign(socket, :item_form, to_form(changeset, as: "todo_item"))}
    end
  end

  def handle_event("toggle_item", %{"id" => id}, socket) do
    item = Todos.get_item!(socket.assigns.current_scope, id)

    case Todos.toggle_item(socket.assigns.current_scope, item) do
      {:ok, item} -> {:noreply, stream_insert(socket, :todo_items, item)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  def handle_event("edit_item", %{"id" => id}, socket) do
    item = Todos.get_item!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> stream_insert(:todo_items, item)
     |> assign(:editing_item_id, item.id)
     |> assign(
       :edit_form,
       to_form(Todos.change_item(socket.assigns.current_scope, item), as: "todo_item_edit")
     )}
  end

  def handle_event("cancel_edit", _params, socket) do
    item = Todos.get_item!(socket.assigns.current_scope, socket.assigns.editing_item_id)

    {:noreply,
     socket
     |> stream_insert(:todo_items, item)
     |> assign(:editing_item_id, nil)
     |> assign(:edit_form, nil)}
  end

  def handle_event("save_item", %{"todo_item_edit" => params}, socket) do
    item = Todos.get_item!(socket.assigns.current_scope, socket.assigns.editing_item_id)

    case Todos.update_item(socket.assigns.current_scope, item, params) do
      {:ok, item} ->
        {:noreply,
         socket
         |> stream_insert(:todo_items, item)
         |> assign(:editing_item_id, nil)
         |> assign(:edit_form, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: "todo_item_edit"))}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Todos.get_item!(socket.assigns.current_scope, id)

    case Todos.delete_item(socket.assigns.current_scope, item) do
      {:ok, item} -> {:noreply, stream_delete(socket, :todo_items, item)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  def handle_event("move_item", %{"id" => id, "direction" => direction}, socket) do
    item = Todos.get_item!(socket.assigns.current_scope, id)
    direction = String.to_existing_atom(direction)

    case Todos.move_item(socket.assigns.current_scope, item, direction) do
      {:ok, _item} -> {:noreply, reset_items(socket)}
    end
  end

  @impl true
  def handle_info({type, %TodoItem{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, reset_items(socket)}
  end

  defp item_form(scope), do: to_form(Todos.change_item(scope, %TodoItem{}), as: "todo_item")

  defp reset_items(socket) do
    stream(
      socket,
      :todo_items,
      Todos.list_items(socket.assigns.current_scope, socket.assigns.todo_list),
      reset: true
    )
  end
end
