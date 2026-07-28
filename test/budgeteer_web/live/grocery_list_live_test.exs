defmodule BudgeteerWeb.GroceryListLiveTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.GroceriesFixtures

  @create_attrs %{name: "Weekly shop"}
  @invalid_attrs %{name: nil}

  setup :register_and_log_in_user

  defp create_grocery_list(%{scope: scope}) do
    %{grocery_list: grocery_list_fixture(scope)}
  end

  describe "Index" do
    setup [:create_grocery_list]

    test "lists active grocery lists", %{conn: conn, grocery_list: grocery_list} do
      {:ok, _index_live, html} = live(conn, ~p"/groceries")

      assert html =~ "Grocery lists"
      assert html =~ grocery_list.name
    end

    test "creates a new grocery list", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/groceries")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New list")
               |> render_click()
               |> follow_redirect(conn, ~p"/groceries/new")

      assert render(form_live) =~ "New grocery list"

      assert form_live
             |> form("#grocery-list-form", grocery_list: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#grocery-list-form", grocery_list: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/groceries")

      html = render(index_live)
      assert html =~ "Grocery list created successfully"
      assert html =~ "Weekly shop"
    end

    test "archives a grocery list from the index", %{conn: conn, grocery_list: grocery_list} do
      {:ok, index_live, _html} = live(conn, ~p"/groceries")

      assert index_live |> element("#grocery_lists-#{grocery_list.id} a", "Archive") |> render_click()
      refute has_element?(index_live, "#grocery_lists-#{grocery_list.id}")
    end

    test "shows archived lists in the archived view and can unarchive", %{
      conn: conn,
      scope: scope,
      grocery_list: grocery_list
    } do
      {:ok, archived} = Budgeteer.Groceries.archive_grocery_list(scope, grocery_list)

      {:ok, index_live, html} = live(conn, ~p"/groceries?archived=true")
      assert html =~ "Archived grocery lists"
      assert has_element?(index_live, "#grocery_lists-#{archived.id}")

      assert index_live |> element("#grocery_lists-#{archived.id} a", "Unarchive") |> render_click()
      refute has_element?(index_live, "#grocery_lists-#{archived.id}")
    end
  end
end
