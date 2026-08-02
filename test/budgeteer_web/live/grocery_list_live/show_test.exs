defmodule BudgeteerWeb.GroceryListLive.ShowTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.GroceriesFixtures
  import Budgeteer.HouseholdsFixtures, only: [second_household_member_fixture: 1]

  alias Budgeteer.Groceries

  setup :register_and_log_in_user

  defp create_grocery_list(%{scope: scope}) do
    %{grocery_list: grocery_list_fixture(scope)}
  end

  describe "Show" do
    setup [:create_grocery_list]

    test "displays the list and its items", %{
      conn: conn,
      scope: scope,
      grocery_list: grocery_list
    } do
      item = grocery_item_fixture(scope, grocery_list, %{name: "Milk", quantity: "2", unit: "l"})

      {:ok, _show_live, html} = live(conn, ~p"/groceries/#{grocery_list}")

      assert html =~ grocery_list.name
      assert html =~ item.name
      assert html =~ "2"
      assert html =~ "l"
    end

    test "adds an item", %{conn: conn, grocery_list: grocery_list} do
      {:ok, show_live, _html} = live(conn, ~p"/groceries/#{grocery_list}")

      html =
        show_live
        |> form("#add-item-form", grocery_item: %{name: "Bread", quantity: "1", unit: "unit"})
        |> render_submit()

      assert html =~ "Bread"
    end

    test "toggles an item checked and unchecked", %{
      conn: conn,
      scope: scope,
      grocery_list: grocery_list
    } do
      item = grocery_item_fixture(scope, grocery_list)
      {:ok, show_live, _html} = live(conn, ~p"/groceries/#{grocery_list}")

      html =
        show_live
        |> element("#items-#{item.id} input[type=checkbox]")
        |> render_click()

      assert html =~ "line-through"
      assert Groceries.get_item!(scope, item.id).checked

      html =
        show_live
        |> element("#items-#{item.id} input[type=checkbox]")
        |> render_click()

      refute html =~ "line-through"
      refute Groceries.get_item!(scope, item.id).checked
    end

    test "deletes an item", %{conn: conn, scope: scope, grocery_list: grocery_list} do
      item = grocery_item_fixture(scope, grocery_list)
      {:ok, show_live, _html} = live(conn, ~p"/groceries/#{grocery_list}")

      assert show_live |> element("#items-#{item.id} a") |> render_click()
      refute has_element?(show_live, "#items-#{item.id}")
    end

    test "does not show a Clear checked button when nothing is checked", %{
      conn: conn,
      scope: scope,
      grocery_list: grocery_list
    } do
      grocery_item_fixture(scope, grocery_list)
      {:ok, show_live, _html} = live(conn, ~p"/groceries/#{grocery_list}")

      refute has_element?(show_live, "button", "Clear checked")
    end

    test "clears every checked item, leaving unchecked items alone", %{
      conn: conn,
      scope: scope,
      grocery_list: grocery_list
    } do
      checked = grocery_item_fixture(scope, grocery_list, %{name: "Milk"})
      unchecked = grocery_item_fixture(scope, grocery_list, %{name: "Eggs"})
      {:ok, _} = Groceries.check_item(scope, checked)

      {:ok, show_live, html} = live(conn, ~p"/groceries/#{grocery_list}")
      assert html =~ "Clear checked"

      html = show_live |> element("button", "Clear checked") |> render_click()

      refute has_element?(show_live, "#items-#{checked.id}")
      assert has_element?(show_live, "#items-#{unchecked.id}")
      refute html =~ "Clear checked"

      assert_raise Ecto.NoResultsError, fn -> Groceries.get_item!(scope, checked.id) end
    end

    test "reflects another household member clearing checked items in real time", %{
      conn: conn,
      scope: scope,
      grocery_list: grocery_list
    } do
      checked = grocery_item_fixture(scope, grocery_list, %{name: "Milk"})
      {:ok, _} = Groceries.check_item(scope, checked)
      member = second_household_member_fixture(scope.user)

      {:ok, viewer_live, _html} = live(conn, ~p"/groceries/#{grocery_list}")

      member_conn = log_in_user(build_conn(), member)
      {:ok, actor_live, _html} = live(member_conn, ~p"/groceries/#{grocery_list}")

      actor_live |> element("button", "Clear checked") |> render_click()

      refute has_element?(viewer_live, "#items-#{checked.id}")
    end

    test "renames the list via the edit form, returns to show", %{
      conn: conn,
      grocery_list: grocery_list
    } do
      {:ok, show_live, _html} = live(conn, ~p"/groceries/#{grocery_list}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Rename")
               |> render_click()
               |> follow_redirect(conn, ~p"/groceries/#{grocery_list}/edit?return_to=show")

      assert {:ok, show_live, html} =
               form_live
               |> form("#grocery-list-form", grocery_list: %{name: "Continente run"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/groceries/#{grocery_list}")

      assert html =~ "Grocery list updated successfully"
      assert html =~ "Continente run"
      assert show_live
    end

    test "reflects another household member checking an item in real time", %{
      conn: conn,
      scope: scope,
      grocery_list: grocery_list
    } do
      item = grocery_item_fixture(scope, grocery_list)
      member = second_household_member_fixture(scope.user)

      {:ok, viewer_live, _html} = live(conn, ~p"/groceries/#{grocery_list}")

      member_conn = log_in_user(build_conn(), member)
      {:ok, actor_live, _html} = live(member_conn, ~p"/groceries/#{grocery_list}")

      actor_live
      |> element("#items-#{item.id} input[type=checkbox]")
      |> render_click()

      assert render(viewer_live) =~ "line-through"
    end
  end
end
