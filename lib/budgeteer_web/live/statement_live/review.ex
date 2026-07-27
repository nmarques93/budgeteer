defmodule BudgeteerWeb.StatementLive.Review do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias Budgeteer.Statements

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        Review {@statement.filename}
        <:subtitle>
          <.link navigate={~p"/accounts/#{@account}/statements"}>Back to statements</.link>
        </:subtitle>
      </.header>

      <p :if={@statement.status != :processed} class="text-warning">
        This statement hasn't finished processing yet — nothing to review.
      </p>

      <p :if={@statement.status == :processed and @rows == []}>
        No transactions were extracted from this statement.
      </p>

      <form :if={@rows != []} id="review-form" phx-submit="save">
        <table class="table">
          <thead>
            <tr>
              <th>Include</th>
              <th>Date</th>
              <th>Amount</th>
              <th>Merchant</th>
              <th>Description</th>
              <th>Category</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows}>
              <td>
                <input type="hidden" name={"rows[#{row.index}][include]"} value="false" />
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  name={"rows[#{row.index}][include]"}
                  value="true"
                  checked
                />
              </td>
              <td><input type="date" class="w-full input" name={"rows[#{row.index}][date]"} value={row.date} /></td>
              <td>
                <input type="text" class="w-full input" name={"rows[#{row.index}][amount]"} value={row.amount} />
              </td>
              <td>
                <input type="text" class="w-full input" name={"rows[#{row.index}][merchant]"} value={row.merchant} />
              </td>
              <td>
                <input
                  type="text"
                  class="w-full input"
                  name={"rows[#{row.index}][description]"}
                  value={row.description}
                />
              </td>
              <td>
                <select class="w-full select" name={"rows[#{row.index}][category_id]"}>
                  <option value="">Uncategorized</option>
                  <option :for={category <- @categories} value={category.id} selected={category.id == row.category_id}>
                    {category.name}
                  </option>
                </select>
                <p :if={row.category_id == nil and row.suggested_category not in [nil, ""]} class="text-xs opacity-70 mt-1">
                  Suggested: "{row.suggested_category}" — not yet a category.
                  <button
                    type="button"
                    class="link"
                    phx-click="create_category"
                    phx-value-index={row.index}
                    phx-value-name={row.suggested_category}
                  >
                    Create it
                  </button>
                </p>
              </td>
            </tr>
          </tbody>
        </table>

        <footer class="mt-4">
          <.button phx-disable-with="Saving..." variant="primary">Save transactions</.button>
          <.button navigate={~p"/accounts/#{@account}/statements"}>Cancel</.button>
        </footer>
      </form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"account_id" => account_id, "id" => id}, _session, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, account_id)
    statement = Statements.get_statement!(socket.assigns.current_scope, id)
    true = statement.account_id == account.id
    categories = Ledger.list_categories(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Review Statement")
     |> assign(:account, account)
     |> assign(:statement, statement)
     |> assign(:categories, categories)
     |> assign(:rows, build_rows(statement, categories))}
  end

  @impl true
  def handle_event("create_category", %{"index" => index_str, "name" => name}, socket) do
    scope = socket.assigns.current_scope
    index = String.to_integer(index_str)
    row = Enum.find(socket.assigns.rows, &(&1.index == index))
    type = if row && String.starts_with?(row.amount || "", "-"), do: :expense, else: :income

    case Ledger.create_category(scope, %{"name" => name, "type" => type}) do
      {:ok, category} ->
        rows = Enum.map(socket.assigns.rows, &assign_if_matching_suggestion(&1, category, name))

        {:noreply,
         socket
         |> assign(:categories, socket.assigns.categories ++ [category])
         |> assign(:rows, rows)
         |> put_flash(:info, "Created category \"#{category.name}\"")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, category_error_message(changeset))}
    end
  end

  def handle_event("save", %{"rows" => rows_params}, socket) do
    scope = socket.assigns.current_scope
    account = socket.assigns.account
    statement = socket.assigns.statement

    {oks, errors} =
      rows_params
      |> Map.values()
      |> Enum.filter(&(&1["include"] == "true"))
      |> Enum.map(&create_transaction_from_row(scope, account, statement, &1))
      |> Enum.split_with(&match?({:ok, _}, &1))

    case errors do
      [] ->
        {:noreply,
         socket
         |> put_flash(:info, "#{length(oks)} transaction(s) saved")
         |> push_navigate(to: ~p"/accounts/#{account}/transactions")}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Saved #{length(oks)}, #{length(errors)} row(s) failed — check the values and try again"
         )}
    end
  end

  defp build_rows(%{raw_ai_output: nil}, _categories), do: []

  defp build_rows(statement, categories) do
    (statement.raw_ai_output["transactions"] || [])
    |> Enum.with_index()
    |> Enum.map(fn {tx, idx} ->
      suggested_category = tx["category"]

      %{
        index: idx,
        date: tx["date"],
        amount: Budgeteer.Money.to_decimal_string(tx["amount_cents"]),
        merchant: tx["merchant"],
        description: tx["description"],
        category_id: matching_category_id(categories, suggested_category),
        suggested_category: suggested_category
      }
    end)
  end

  defp assign_if_matching_suggestion(row, category, suggested_name) do
    if row.category_id == nil and row.suggested_category not in [nil, ""] and
         String.downcase(String.trim(row.suggested_category)) == String.downcase(String.trim(suggested_name)) do
      %{row | category_id: category.id}
    else
      row
    end
  end

  defp category_error_message(changeset) do
    case changeset.errors[:name] do
      {msg, _opts} -> "Category name #{msg}"
      nil -> "Could not create category"
    end
  end

  defp matching_category_id(_categories, suggested) when suggested in [nil, ""], do: nil

  defp matching_category_id(categories, suggested) do
    normalized = String.downcase(String.trim(suggested))

    case Enum.find(categories, &(String.downcase(&1.name) == normalized)) do
      nil -> nil
      category -> category.id
    end
  end

  defp create_transaction_from_row(scope, account, statement, row_params) do
    attrs = %{
      "date" => row_params["date"],
      "amount" => row_params["amount"],
      "merchant" => row_params["merchant"],
      "description" => row_params["description"],
      "category_id" => blank_to_nil(row_params["category_id"]),
      "account_id" => account.id,
      "statement_id" => statement.id
    }

    Ledger.create_transaction(scope, attrs)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val
end
