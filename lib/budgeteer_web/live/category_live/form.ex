defmodule BudgeteerWeb.CategoryLive.Form do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias Budgeteer.Ledger.Category

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="category-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:color]} type="text" label={gettext("Color")} />
        <.input
          field={@form[:icon]}
          type="select"
          label={gettext("Icon")}
          options={icon_options()}
        />
        <.input
          field={@form[:budget]}
          type="text"
          label={gettext("Budget")}
          placeholder={gettext("e.g. 150.00")}
        />
        <.input
          field={@form[:type]}
          type="select"
          label={gettext("Type")}
          prompt={gettext("Choose a value")}
          options={Ecto.Enum.values(Budgeteer.Ledger.Category, :type)}
        />
        <footer>
          <.button phx-disable-with={gettext("Saving...")} variant="primary">
            {gettext("Save Category")}
          </.button>
          <.button navigate={return_path(@current_scope, @return_to, @category)}>
            {gettext("Cancel")}
          </.button>
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
    category = Ledger.get_category!(socket.assigns.current_scope, id)
    category = %{category | budget: Budgeteer.Money.to_decimal_string(category.budget_cents)}

    socket
    |> assign(:page_title, gettext("Edit Category"))
    |> assign(:category, category)
    |> assign(:form, to_form(Ledger.change_category(socket.assigns.current_scope, category)))
  end

  defp apply_action(socket, :new, _params) do
    category = %Category{household_id: socket.assigns.current_scope.user.household_id}

    socket
    |> assign(:page_title, gettext("New Category"))
    |> assign(:category, category)
    |> assign(:form, to_form(Ledger.change_category(socket.assigns.current_scope, category)))
  end

  @impl true
  def handle_event("validate", %{"category" => category_params}, socket) do
    changeset =
      Ledger.change_category(
        socket.assigns.current_scope,
        socket.assigns.category,
        category_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"category" => category_params}, socket) do
    save_category(socket, socket.assigns.live_action, category_params)
  end

  defp save_category(socket, :edit, category_params) do
    case Ledger.update_category(
           socket.assigns.current_scope,
           socket.assigns.category,
           category_params
         ) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Category updated successfully"))
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, category)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_category(socket, :new, category_params) do
    case Ledger.create_category(socket.assigns.current_scope, category_params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Category created successfully"))
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, category)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _category), do: ~p"/categories"
  defp return_path(_scope, "show", category), do: ~p"/categories/#{category}"

  defp icon_options do
    [
      {gettext("Tag"), "hero-tag"},
      {gettext("Shopping"), "hero-shopping-cart"},
      {gettext("Home"), "hero-home"},
      {gettext("Utilities"), "hero-bolt"},
      {gettext("Health"), "hero-heart"},
      {gettext("Entertainment"), "hero-film"},
      {gettext("Education"), "hero-academic-cap"},
      {gettext("Finance"), "hero-banknotes"},
      {gettext("Transport"), "hero-truck"},
      {gettext("Gifts"), "hero-gift"},
      {gettext("Food"), "hero-beaker"},
      {gettext("Phone"), "hero-device-phone-mobile"},
      {gettext("Tools"), "hero-wrench-screwdriver"},
      {gettext("Work"), "hero-briefcase"},
      {gettext("Office"), "hero-building-office-2"},
      {gettext("Special"), "hero-sparkles"}
    ]
  end
end
