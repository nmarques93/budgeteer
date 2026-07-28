defmodule Budgeteer.GroceriesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Budgeteer.Groceries` context.
  """

  def grocery_list_fixture(scope, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "some list #{System.unique_integer()}"})

    {:ok, grocery_list} = Budgeteer.Groceries.create_grocery_list(scope, attrs)
    grocery_list
  end

  def grocery_item_fixture(scope, grocery_list, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "some item #{System.unique_integer()}"})

    {:ok, grocery_item} = Budgeteer.Groceries.create_item(scope, grocery_list, attrs)
    grocery_item
  end
end
