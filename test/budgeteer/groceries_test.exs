defmodule Budgeteer.GroceriesTest do
  use Budgeteer.DataCase

  alias Budgeteer.Groceries

  import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
  import Budgeteer.GroceriesFixtures

  describe "grocery_lists" do
    alias Budgeteer.Groceries.GroceryList

    @invalid_attrs %{name: nil}

    test "list_grocery_lists/2 returns active, scoped lists by default" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      other_grocery_list = grocery_list_fixture(other_scope)

      assert Groceries.list_grocery_lists(scope) == [grocery_list]
      assert Groceries.list_grocery_lists(other_scope) == [other_grocery_list]
    end

    test "list_grocery_lists/2 excludes archived lists by default, includes with archived: true" do
      scope = household_scope_fixture()
      active = grocery_list_fixture(scope)
      archived = grocery_list_fixture(scope)
      {:ok, archived} = Groceries.archive_grocery_list(scope, archived)

      assert Groceries.list_grocery_lists(scope) == [active]
      assert Groceries.list_grocery_lists(scope, archived: true) == [archived]
    end

    test "get_grocery_list!/2 returns the grocery list with given id, scoped" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      other_scope = household_scope_fixture()

      assert Groceries.get_grocery_list!(scope, grocery_list.id) == grocery_list

      assert_raise Ecto.NoResultsError, fn ->
        Groceries.get_grocery_list!(other_scope, grocery_list.id)
      end
    end

    test "create_grocery_list/2 with valid data creates a grocery list" do
      scope = household_scope_fixture()
      valid_attrs = %{name: "Weekly shop"}

      assert {:ok, %GroceryList{} = grocery_list} =
               Groceries.create_grocery_list(scope, valid_attrs)

      assert grocery_list.name == "Weekly shop"
      assert grocery_list.household_id == scope.user.household_id
      assert is_nil(grocery_list.archived_at)
    end

    test "create_grocery_list/2 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Groceries.create_grocery_list(scope, @invalid_attrs)
    end

    test "update_grocery_list/3 with valid data updates the name" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      assert {:ok, %GroceryList{} = grocery_list} =
               Groceries.update_grocery_list(scope, grocery_list, %{name: "Continente run"})

      assert grocery_list.name == "Continente run"
    end

    test "update_grocery_list/3 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      assert_raise MatchError, fn ->
        Groceries.update_grocery_list(other_scope, grocery_list, %{})
      end
    end

    test "archive_grocery_list/2 sets archived_at and unarchive_grocery_list/2 clears it" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      assert {:ok, archived} = Groceries.archive_grocery_list(scope, grocery_list)
      refute is_nil(archived.archived_at)

      assert {:ok, unarchived} = Groceries.unarchive_grocery_list(scope, archived)
      assert is_nil(unarchived.archived_at)
    end

    test "change_grocery_list/2 returns a grocery list changeset" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      assert %Ecto.Changeset{} = Groceries.change_grocery_list(scope, grocery_list)
    end
  end

  describe "grocery_items" do
    alias Budgeteer.Groceries.GroceryItem

    @invalid_attrs %{name: nil}

    test "list_items/2 returns items scoped to the given list" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      other_list = grocery_list_fixture(scope)
      item = grocery_item_fixture(scope, grocery_list)
      _other_item = grocery_item_fixture(scope, other_list)

      assert Groceries.list_items(scope, grocery_list) == [item]
    end

    test "list_items/2 orders items by category's fixed store-aisle order, then name, with uncategorized items last" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      bread = grocery_item_fixture(scope, grocery_list, %{name: "Bread", category: "Bakery"})
      milk = grocery_item_fixture(scope, grocery_list, %{name: "Milk", category: "Dairy & Eggs"})
      eggs = grocery_item_fixture(scope, grocery_list, %{name: "Eggs", category: "Dairy & Eggs"})
      soap = grocery_item_fixture(scope, grocery_list, %{name: "Soap"})

      # Dairy & Eggs sorts before Bakery per GroceryItem.categories/0's own
      # order; within a category, alphabetical by name (Eggs before Milk).
      assert Groceries.list_items(scope, grocery_list) == [eggs, milk, bread, soap]
    end

    test "create_item/3 rejects a category outside the fixed list" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      assert {:error, changeset} =
               Groceries.create_item(scope, grocery_list, %{name: "Milk", category: "Snacks"})

      assert "is invalid" in errors_on(changeset).category
    end

    test "get_item!/2 returns the item with given id, scoped" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      item = grocery_item_fixture(scope, grocery_list)
      other_scope = household_scope_fixture()

      assert Groceries.get_item!(scope, item.id) == item
      assert_raise Ecto.NoResultsError, fn -> Groceries.get_item!(other_scope, item.id) end
    end

    test "create_item/3 with valid data adds an item to the list" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      valid_attrs = %{name: "Milk", quantity: "2", unit: "l"}

      assert {:ok, %GroceryItem{} = item} =
               Groceries.create_item(scope, grocery_list, valid_attrs)

      assert item.name == "Milk"
      assert Decimal.equal?(item.quantity, Decimal.new("2"))
      assert item.unit == "l"
      assert item.grocery_list_id == grocery_list.id
      assert item.household_id == scope.user.household_id
      assert item.added_by_id == scope.user.id
      refute item.checked
    end

    test "create_item/3 with invalid data returns error changeset" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      assert {:error, %Ecto.Changeset{}} =
               Groceries.create_item(scope, grocery_list, @invalid_attrs)
    end

    test "delete_item/2 deletes the item" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      item = grocery_item_fixture(scope, grocery_list)

      assert {:ok, %GroceryItem{}} = Groceries.delete_item(scope, item)
      assert_raise Ecto.NoResultsError, fn -> Groceries.get_item!(scope, item.id) end
    end

    test "delete_item/2 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      item = grocery_item_fixture(scope, grocery_list)

      assert_raise MatchError, fn -> Groceries.delete_item(other_scope, item) end
    end

    test "check_item/2 marks the item checked and records who checked it" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      item = grocery_item_fixture(scope, grocery_list)

      assert {:ok, checked} = Groceries.check_item(scope, item)
      assert checked.checked
      assert checked.checked_by_id == scope.user.id
    end

    test "uncheck_item/2 clears checked and checked_by_id" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      item = grocery_item_fixture(scope, grocery_list)
      {:ok, checked} = Groceries.check_item(scope, item)

      assert {:ok, unchecked} = Groceries.uncheck_item(scope, checked)
      refute unchecked.checked
      assert is_nil(unchecked.checked_by_id)
    end

    test "change_item/2 returns an item changeset" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      item = grocery_item_fixture(scope, grocery_list)
      assert %Ecto.Changeset{} = Groceries.change_item(scope, item)
    end

    test "delete_checked_items/2 deletes only the checked items on the list" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      checked1 = grocery_item_fixture(scope, grocery_list, %{name: "Milk"})
      checked2 = grocery_item_fixture(scope, grocery_list, %{name: "Bread"})
      unchecked = grocery_item_fixture(scope, grocery_list, %{name: "Eggs"})

      {:ok, _} = Groceries.check_item(scope, checked1)
      {:ok, _} = Groceries.check_item(scope, checked2)

      assert {:ok, deleted} = Groceries.delete_checked_items(scope, grocery_list)
      assert Enum.map(deleted, & &1.id) |> Enum.sort() == Enum.sort([checked1.id, checked2.id])

      remaining_names =
        Groceries.list_items(scope, grocery_list) |> Enum.map(& &1.name)

      assert remaining_names == [unchecked.name]
    end

    test "delete_checked_items/2 does nothing when no items are checked" do
      scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)
      grocery_item_fixture(scope, grocery_list)

      assert {:ok, []} = Groceries.delete_checked_items(scope, grocery_list)
      assert length(Groceries.list_items(scope, grocery_list)) == 1
    end

    test "delete_checked_items/2 with invalid scope raises" do
      scope = household_scope_fixture()
      other_scope = household_scope_fixture()
      grocery_list = grocery_list_fixture(scope)

      assert_raise MatchError, fn -> Groceries.delete_checked_items(other_scope, grocery_list) end
    end
  end
end
