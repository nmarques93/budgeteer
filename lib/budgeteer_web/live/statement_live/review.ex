defmodule BudgeteerWeb.StatementLive.Review do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger
  alias Budgeteer.Ledger.TransactionFingerprint
  alias Budgeteer.Statements

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {gettext("Review %{filename}", filename: @statement.filename)}
        <:subtitle>
          <.link navigate={~p"/accounts/#{@account}/statements"}>{gettext("Back to statements")}</.link>
        </:subtitle>
      </.header>

      <p :if={@statement.status != :processed} class="text-warning">
        {gettext("This statement isn't ready to review yet.")}
      </p>

      <p :if={@statement.status == :processed and @rows == []}>
        {gettext("No transactions were extracted from this statement.")}
      </p>

      <div
        :if={@duplicate_count > 0 or @incomplete_count > 0}
        id="review-warnings"
        class="alert alert-warning mb-4"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <div>
          <p :if={@duplicate_count > 0}>
            {ngettext(
              "%{count} row appears to duplicate an existing transaction.",
              "%{count} rows appear to duplicate existing transactions.",
              @duplicate_count
            )}
          </p>
          <p :if={@incomplete_count > 0}>
            {ngettext(
              "%{count} row is incomplete and was left unchecked.",
              "%{count} rows are incomplete and were left unchecked.",
              @incomplete_count
            )}
          </p>
          <p :if={@skipped_count > 0} class="text-sm">
            {ngettext(
              "%{count} flagged row will be skipped unless included.",
              "%{count} flagged rows will be skipped unless included.",
              @skipped_count
            )}
          </p>
          <p class="text-sm opacity-80">
            {gettext(
              "Review flagged rows before saving. You can include one deliberately if it is legitimate."
            )}
          </p>
        </div>
      </div>

      <div
        :if={@reconciliation.status == :match}
        id="balance-reconciliation"
        class="alert alert-success mb-4"
      >
        <.icon name="hero-check-circle" class="size-5 shrink-0" />
        {gettext("Statement balance reconciles at %{amount}.",
          amount: Budgeteer.Money.format(@reconciliation.closing_balance_cents)
        )}
      </div>
      <div
        :if={@reconciliation.status == :mismatch}
        id="balance-reconciliation"
        class="alert alert-error mb-4"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        {gettext(
          "Balance mismatch: expected %{expected}, statement says %{closing} (difference %{difference}).",
          expected: Budgeteer.Money.format(@reconciliation.expected_closing_balance_cents),
          closing: Budgeteer.Money.format(@reconciliation.closing_balance_cents),
          difference: Budgeteer.Money.format(@reconciliation.difference_cents)
        )}
      </div>
      <p :if={@reconciliation.status == :unavailable} class="text-sm opacity-70 mb-4">
        {gettext("Opening and closing balances were not available for this statement.")}
      </p>

      <form :if={@rows != []} id="review-form" phx-submit="save">
        <div class="overflow-x-auto">
          <table class="table block md:table">
            <thead class="hidden md:table-header-group">
              <tr>
                <th>{gettext("Include")}</th>
                <th>{gettext("Date")}</th>
                <th>{gettext("Amount")}</th>
                <th>{gettext("Merchant")}</th>
                <th>{gettext("Description")}</th>
                <th>{gettext("Category")}</th>
              </tr>
            </thead>
            <tbody class="block md:table-row-group">
              <tr
                :for={row <- @rows}
                class="block md:table-row border border-base-300 rounded-box mb-3 p-3 md:border-0 md:mb-0 md:p-0"
              >
                <td class="block md:table-cell align-top pt-2 md:pt-4">
                  <span class="md:hidden block text-xs font-semibold opacity-60 mb-1">{gettext(
                    "Include"
                  )}</span>
                  <input type="hidden" name={"rows[#{row.index}][include]"} value="false" />
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    name={"rows[#{row.index}][include]"}
                    value="true"
                    checked={not row.duplicate? and not row.incomplete?}
                  />
                  <span :if={row.duplicate?} class="block text-xs text-error mt-1">{gettext(
                    "Duplicate"
                  )}</span>
                  <span :if={row.incomplete?} class="block text-xs text-warning mt-1">{gettext(
                    "Incomplete"
                  )}</span>
                </td>
                <td class="block md:table-cell align-top">
                  <span class="md:hidden block text-xs font-semibold opacity-60 mb-1">{gettext("Date")}</span>
                  <input
                    type="date"
                    class="w-full input"
                    name={"rows[#{row.index}][date]"}
                    value={row.date}
                  />
                </td>
                <td class="block md:table-cell align-top">
                  <span class="md:hidden block text-xs font-semibold opacity-60 mb-1">{gettext(
                    "Amount"
                  )}</span>
                  <input
                    type="text"
                    class="w-full input"
                    name={"rows[#{row.index}][amount]"}
                    value={row.amount}
                  />
                </td>
                <td class="block md:table-cell align-top">
                  <span class="md:hidden block text-xs font-semibold opacity-60 mb-1">{gettext(
                    "Merchant"
                  )}</span>
                  <input
                    type="text"
                    class="w-full input"
                    name={"rows[#{row.index}][merchant]"}
                    value={row.merchant}
                  />
                </td>
                <td class="block md:table-cell align-top">
                  <span class="md:hidden block text-xs font-semibold opacity-60 mb-1">{gettext(
                    "Description"
                  )}</span>
                  <input
                    type="text"
                    class="w-full input"
                    name={"rows[#{row.index}][description]"}
                    value={row.description}
                  />
                </td>
                <td class="block md:table-cell align-top min-w-56">
                  <span class="md:hidden block text-xs font-semibold opacity-60 mb-1">{gettext(
                    "Category"
                  )}</span>
                  <select class="w-full select min-w-40" name={"rows[#{row.index}][category_id]"}>
                    <option value="">{gettext("Uncategorized")}</option>
                    <option
                      :for={category <- @categories}
                      value={category.id}
                      selected={category.id == row.category_id}
                    >
                      {category.name}
                    </option>
                  </select>
                  <p
                    :if={row.category_id == nil and row.suggested_category not in [nil, ""]}
                    class="text-xs opacity-70 mt-1 max-w-56"
                  >
                    {gettext("Suggested: \"%{name}\" — not yet a category.",
                      name: row.suggested_category
                    )}
                    <button
                      type="button"
                      class="link"
                      phx-click="create_category"
                      phx-value-index={row.index}
                      phx-value-name={row.suggested_category}
                    >
                      {gettext("Create it")}
                    </button>
                  </p>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <footer class="mt-4">
          <.button phx-disable-with={gettext("Saving...")} variant="primary">
            {gettext("Save transactions")}
          </.button>
          <.button navigate={~p"/accounts/#{@account}/statements"}>{gettext("Cancel")}</.button>
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
     |> assign(:page_title, gettext("Review Statement"))
     |> assign(:account, account)
     |> assign(:statement, statement)
     |> assign(:categories, categories)
     |> assign(
       :rows,
       build_rows(
         statement,
         categories,
         Ledger.list_transaction_fingerprints(socket.assigns.current_scope, account.id)
       )
     )
     |> assign(:duplicate_count, 0)
     |> assign(:incomplete_count, 0)
     |> assign_review_metrics()}
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
         |> assign_review_metrics()
         |> put_flash(:info, gettext("Created category \"%{name}\"", name: category.name))}

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
        {:ok, _statement} = Statements.clear_reviewed(scope, statement)

        {:noreply,
         socket
         |> put_flash(
           :info,
           ngettext("1 transaction saved", "%{count} transactions saved", length(oks))
         )
         |> push_navigate(to: ~p"/accounts/#{account}/transactions")}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "Saved %{ok_count}, %{error_count} row(s) failed — check the values and try again",
             ok_count: length(oks),
             error_count: length(errors)
           )
         )}
    end
  end

  defp build_rows(%{raw_ai_output: nil}, _categories, _existing_fingerprints), do: []

  defp build_rows(statement, categories, existing_fingerprints) do
    raw_rows =
      (statement.raw_ai_output["transactions"] || [])
      |> Enum.with_index()
      |> Enum.map(fn {tx, idx} ->
        amount_cents = tx["amount_cents"]
        date = tx["date"]
        merchant = tx["merchant"]
        description = tx["description"]
        fingerprint = TransactionFingerprint.build(date, amount_cents, merchant, description)

        %{
          index: idx,
          date: date,
          amount_cents: amount_cents,
          amount: Budgeteer.Money.to_decimal_string(amount_cents),
          merchant: merchant,
          description: description,
          category_id: matching_category_id(categories, tx["category"]),
          suggested_category: tx["category"],
          fingerprint: fingerprint,
          incomplete?: incomplete_row?(date, amount_cents, merchant, description),
          duplicate?: false
        }
      end)

    frequencies =
      raw_rows |> Enum.map(& &1.fingerprint) |> Enum.reject(&is_nil/1) |> Enum.frequencies()

    Enum.map(raw_rows, fn row ->
      %{
        row
        | duplicate?:
            row.fingerprint in existing_fingerprints or
              Map.get(frequencies, row.fingerprint, 0) > 1
      }
    end)
  end

  defp assign_review_metrics(socket) do
    rows = socket.assigns.rows

    socket =
      assign(socket,
        duplicate_count: Enum.count(rows, & &1.duplicate?),
        incomplete_count: Enum.count(rows, & &1.incomplete?)
      )

    assign(socket,
      skipped_count: Enum.count(rows, &(&1.duplicate? or &1.incomplete?)),
      reconciliation: reconciliation(socket.assigns.statement, rows)
    )
  end

  defp reconciliation(statement, rows) do
    opening = statement.opening_balance_cents
    closing = statement.closing_balance_cents
    amounts = rows |> Enum.map(& &1.amount_cents) |> Enum.filter(&is_integer/1)

    cond do
      not is_integer(opening) or not is_integer(closing) ->
        %{status: :unavailable}

      true ->
        expected = opening + Enum.sum(amounts)

        %{
          status: if(expected == closing, do: :match, else: :mismatch),
          expected_closing_balance_cents: expected,
          closing_balance_cents: closing,
          difference_cents: expected - closing
        }
    end
  end

  defp incomplete_row?(date, amount_cents, merchant, description) do
    date in [nil, ""] or not is_integer(amount_cents) or
      (amount_cents == 0 and blank?(merchant) and blank?(description))
  end

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(to_string(value)) == ""

  defp assign_if_matching_suggestion(row, category, suggested_name) do
    if row.category_id == nil and row.suggested_category not in [nil, ""] and
         String.downcase(String.trim(row.suggested_category)) ==
           String.downcase(String.trim(suggested_name)) do
      %{row | category_id: category.id}
    else
      row
    end
  end

  defp category_error_message(changeset) do
    case changeset.errors[:name] do
      {_msg, _opts} = error ->
        gettext("Category name %{message}",
          message: BudgeteerWeb.CoreComponents.translate_error(error)
        )

      nil ->
        gettext("Could not create category")
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
