defmodule Budgeteer.Groceries do
  @moduledoc """
  The Groceries context — shared household shopping lists. Items are
  broadcast on a topic scoped to their own list (not a household-wide
  items topic), so viewing one list doesn't receive PubSub noise from
  every other list in the household.
  """

  import Ecto.Query, warn: false
  alias Budgeteer.Repo

  alias Budgeteer.Groceries.{GroceryList, GroceryItem}
  alias Budgeteer.Households.Scope

  ## Grocery lists

  @doc """
  Subscribes to scoped notifications about grocery list changes.

  The broadcasted messages match the pattern:

    * {:created, %GroceryList{}}
    * {:updated, %GroceryList{}}

  """
  def subscribe_grocery_lists(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{scope.user.household_id}:grocery_lists")
  end

  defp broadcast_grocery_list(household_id, message) do
    Phoenix.PubSub.broadcast(Budgeteer.PubSub, "household:#{household_id}:grocery_lists", message)
  end

  @doc """
  Returns the household's grocery lists. Active (non-archived) by
  default; pass `archived: true` for archived ones.
  """
  def list_grocery_lists(%Scope{} = scope, opts \\ []) do
    archived? = Keyword.get(opts, :archived, false)

    query =
      from l in GroceryList,
        where: l.household_id == ^scope.user.household_id,
        order_by: [desc: l.inserted_at]

    query =
      if archived? do
        where(query, [l], not is_nil(l.archived_at))
      else
        where(query, [l], is_nil(l.archived_at))
      end

    Repo.all(query)
  end

  @doc """
  Gets a single grocery list, scoped to the household.
  """
  def get_grocery_list!(%Scope{} = scope, id) do
    Repo.get_by!(GroceryList, id: id, household_id: scope.user.household_id)
  end

  @doc """
  Creates a grocery list.
  """
  def create_grocery_list(%Scope{} = scope, attrs) do
    with {:ok, grocery_list = %GroceryList{}} <-
           %GroceryList{}
           |> GroceryList.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_grocery_list(grocery_list.household_id, {:created, grocery_list})
      {:ok, grocery_list}
    end
  end

  @doc """
  Updates a grocery list's name.
  """
  def update_grocery_list(%Scope{} = scope, %GroceryList{} = grocery_list, attrs) do
    true = grocery_list.household_id == scope.user.household_id

    with {:ok, grocery_list = %GroceryList{}} <-
           grocery_list
           |> GroceryList.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_grocery_list(grocery_list.household_id, {:updated, grocery_list})
      {:ok, grocery_list}
    end
  end

  @doc """
  Archives a grocery list.
  """
  def archive_grocery_list(%Scope{} = scope, %GroceryList{} = grocery_list) do
    set_archived_at(scope, grocery_list, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc """
  Unarchives a grocery list.
  """
  def unarchive_grocery_list(%Scope{} = scope, %GroceryList{} = grocery_list) do
    set_archived_at(scope, grocery_list, nil)
  end

  defp set_archived_at(%Scope{} = scope, %GroceryList{} = grocery_list, archived_at) do
    true = grocery_list.household_id == scope.user.household_id

    with {:ok, grocery_list = %GroceryList{}} <-
           grocery_list
           |> Ecto.Changeset.change(archived_at: archived_at)
           |> Repo.update() do
      broadcast_grocery_list(grocery_list.household_id, {:updated, grocery_list})
      {:ok, grocery_list}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking grocery list changes.
  """
  def change_grocery_list(%Scope{} = scope, %GroceryList{} = grocery_list, attrs \\ %{}) do
    GroceryList.changeset(grocery_list, attrs, scope)
  end

  ## Grocery items

  @doc """
  Subscribes to scoped notifications about a specific list's items.

  The broadcasted messages match the pattern:

    * {:created, %GroceryItem{}}
    * {:updated, %GroceryItem{}}
    * {:deleted, %GroceryItem{}}

  """
  def subscribe_items(%Scope{} = scope, %GroceryList{} = grocery_list) do
    true = grocery_list.household_id == scope.user.household_id

    Phoenix.PubSub.subscribe(
      Budgeteer.PubSub,
      "household:#{scope.user.household_id}:grocery_lists:#{grocery_list.id}:items"
    )
  end

  defp broadcast_item(%GroceryItem{} = item, message) do
    Phoenix.PubSub.broadcast(
      Budgeteer.PubSub,
      "household:#{item.household_id}:grocery_lists:#{item.grocery_list_id}:items",
      message
    )
  end

  @doc """
  Returns the items on a grocery list.
  """
  def list_items(%Scope{} = scope, %GroceryList{} = grocery_list) do
    true = grocery_list.household_id == scope.user.household_id

    Repo.all_by(GroceryItem, grocery_list_id: grocery_list.id, household_id: scope.user.household_id)
  end

  @doc """
  Gets a single grocery item, scoped to the household.
  """
  def get_item!(%Scope{} = scope, id) do
    Repo.get_by!(GroceryItem, id: id, household_id: scope.user.household_id)
  end

  @doc """
  Adds an item to a grocery list.
  """
  def create_item(%Scope{} = scope, %GroceryList{} = grocery_list, attrs) do
    true = grocery_list.household_id == scope.user.household_id

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("grocery_list_id", grocery_list.id)
      |> Map.put("added_by_id", scope.user.id)

    with {:ok, item = %GroceryItem{}} <-
           %GroceryItem{}
           |> GroceryItem.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_item(item, {:created, item})
      {:ok, item}
    end
  end

  @doc """
  Deletes a grocery item.
  """
  def delete_item(%Scope{} = scope, %GroceryItem{} = item) do
    true = item.household_id == scope.user.household_id

    with {:ok, item = %GroceryItem{}} <- Repo.delete(item) do
      broadcast_item(item, {:deleted, item})
      {:ok, item}
    end
  end

  @doc """
  Checks off a grocery item, recording who checked it.
  """
  def check_item(%Scope{} = scope, %GroceryItem{} = item) do
    set_checked(scope, item, %{"checked" => true, "checked_by_id" => scope.user.id})
  end

  @doc """
  Unchecks a grocery item. Clears `checked_by_id` — it only means
  something while the item is checked.
  """
  def uncheck_item(%Scope{} = scope, %GroceryItem{} = item) do
    set_checked(scope, item, %{"checked" => false, "checked_by_id" => nil})
  end

  defp set_checked(%Scope{} = scope, %GroceryItem{} = item, attrs) do
    true = item.household_id == scope.user.household_id

    with {:ok, item = %GroceryItem{}} <-
           item
           |> GroceryItem.checked_changeset(attrs)
           |> Repo.update() do
      broadcast_item(item, {:updated, item})
      {:ok, item}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking grocery item changes.
  """
  def change_item(%Scope{} = scope, %GroceryItem{} = item, attrs \\ %{}) do
    GroceryItem.changeset(item, attrs, scope)
  end
end
