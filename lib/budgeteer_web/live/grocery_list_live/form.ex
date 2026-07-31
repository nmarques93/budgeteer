defmodule BudgeteerWeb.GroceryListLive.Form do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Groceries
  alias Budgeteer.Groceries.GroceryList

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {@page_title}
        <:subtitle>{gettext("Use this form to manage grocery lists.")}</:subtitle>
      </.header>

      <.form for={@form} id="grocery-list-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <footer>
          <.button phx-disable-with={gettext("Saving...")} variant="primary">
            {gettext("Save list")}
          </.button>
          <.button navigate={return_path(@return_to, @grocery_list)}>{gettext("Cancel")}</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    grocery_list = Groceries.get_grocery_list!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, gettext("Edit grocery list"))
    |> assign(:grocery_list, grocery_list)
    |> assign(
      :form,
      to_form(Groceries.change_grocery_list(socket.assigns.current_scope, grocery_list))
    )
  end

  defp apply_action(socket, :new, _params) do
    grocery_list = %GroceryList{household_id: socket.assigns.current_scope.user.household_id}

    socket
    |> assign(:page_title, gettext("New grocery list"))
    |> assign(:grocery_list, grocery_list)
    |> assign(
      :form,
      to_form(Groceries.change_grocery_list(socket.assigns.current_scope, grocery_list))
    )
  end

  @impl true
  def handle_event("validate", %{"grocery_list" => params}, socket) do
    changeset =
      Groceries.change_grocery_list(
        socket.assigns.current_scope,
        socket.assigns.grocery_list,
        params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"grocery_list" => params}, socket) do
    save_grocery_list(socket, socket.assigns.live_action, params)
  end

  defp save_grocery_list(socket, :edit, params) do
    case Groceries.update_grocery_list(
           socket.assigns.current_scope,
           socket.assigns.grocery_list,
           params
         ) do
      {:ok, grocery_list} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Grocery list updated successfully"))
         |> push_navigate(to: return_path(socket.assigns.return_to, grocery_list))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_grocery_list(socket, :new, params) do
    case Groceries.create_grocery_list(socket.assigns.current_scope, params) do
      {:ok, grocery_list} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Grocery list created successfully"))
         |> push_navigate(to: return_path(socket.assigns.return_to, grocery_list))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _grocery_list), do: ~p"/groceries"
  defp return_path("show", grocery_list), do: ~p"/groceries/#{grocery_list}"
end
