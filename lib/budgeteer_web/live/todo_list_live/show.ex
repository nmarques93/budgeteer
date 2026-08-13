defmodule BudgeteerWeb.TodoListLive.Show do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Todos
  alias Budgeteer.Todos.TodoItem
  alias Budgeteer.Households

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
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-[minmax(0,1fr)_auto_auto_auto_auto_auto] gap-2 items-end mt-4"
      >
        <.input
          field={@item_form[:title]}
          type="text"
          label={gettext("Task")}
          placeholder={gettext("e.g. Book dentist appointment")}
        />
        <.input field={@item_form[:due_date]} type="date" label={gettext("Due date")} />
        <.input
          field={@item_form[:assignee_id]}
          type="select"
          label={gettext("Assign to")}
          prompt={gettext("Anyone")}
          options={member_options(@members)}
        />
        <.input
          field={@item_form[:priority]}
          type="select"
          label={gettext("Priority")}
          options={priority_options()}
        />
        <.input
          field={@item_form[:recurrence]}
          type="select"
          label={gettext("Repeat")}
          options={recurrence_options()}
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
              <.input
                field={@edit_form[:assignee_id]}
                type="select"
                label={gettext("Assign to")}
                prompt={gettext("Anyone")}
                options={member_options(@members)}
              />
              <.input
                field={@edit_form[:priority]}
                type="select"
                label={gettext("Priority")}
                options={priority_options()}
              />
              <.input
                field={@edit_form[:recurrence]}
                type="select"
                label={gettext("Repeat")}
                options={recurrence_options()}
              />
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
                <p :if={due_label(item)} class={due_class(item)}>
                  {due_label(item)}
                </p>
                <span class={priority_class(item.priority)}>{priority_label(item.priority)}</span>
                <span :if={item.recurrence != :none} class="badge badge-info badge-sm mt-2 ml-1">
                  {recurrence_label(item.recurrence)}
                </span>
                <span :if={item.assignee} class="text-xs opacity-60 ml-2">{display_name(item.assignee)}</span>
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
     |> assign(:members, Households.list_household_members(socket.assigns.current_scope))
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

  defp member_options(members), do: Enum.map(members, &{display_name(&1), &1.id})

  defp display_name(member), do: member.name || member.email

  defp priority_options do
    [{gettext("Low"), "low"}, {gettext("Normal"), "normal"}, {gettext("High"), "high"}]
  end

  defp priority_label(:low), do: gettext("Low")
  defp priority_label(:high), do: gettext("High")
  defp priority_label(_), do: gettext("Normal")

  defp priority_class(:high), do: "badge badge-error badge-sm mt-2"
  defp priority_class(:low), do: "badge badge-ghost badge-sm mt-2"
  defp priority_class(_), do: "badge badge-warning badge-sm mt-2"

  defp recurrence_options do
    [
      {gettext("Does not repeat"), "none"},
      {gettext("Daily"), "daily"},
      {gettext("Weekly"), "weekly"},
      {gettext("Monthly"), "monthly"}
    ]
  end

  defp recurrence_label(:daily), do: gettext("Daily")
  defp recurrence_label(:weekly), do: gettext("Weekly")
  defp recurrence_label(:monthly), do: gettext("Monthly")

  defp due_label(%TodoItem{completed: true}), do: nil
  defp due_label(%TodoItem{due_date: nil}), do: nil

  defp due_label(%TodoItem{due_date: due_date}) do
    case Date.compare(due_date, Date.utc_today()) do
      :lt -> gettext("Overdue · %{date}", date: due_date)
      :eq -> gettext("Due today")
      :gt -> gettext("Due %{date}", date: due_date)
    end
  end

  defp due_class(%TodoItem{due_date: due_date}) do
    class = "text-xs mt-1"

    case Date.compare(due_date, Date.utc_today()) do
      :lt -> class <> " text-error font-semibold"
      :eq -> class <> " text-warning font-semibold"
      :gt -> class <> " opacity-60"
    end
  end

  defp reset_items(socket) do
    stream(
      socket,
      :todo_items,
      Todos.list_items(socket.assigns.current_scope, socket.assigns.todo_list),
      reset: true
    )
  end
end
