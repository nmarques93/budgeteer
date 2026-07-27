defmodule BudgeteerWeb.PresenceHooksTest do
  use BudgeteerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Budgeteer.HouseholdsFixtures

  test "shows another connected household member as online, and removes them on disconnect", %{conn: conn} do
    owner = user_fixture()
    member = second_household_member_fixture(owner)

    Phoenix.PubSub.subscribe(Budgeteer.PubSub, "household:#{owner.household_id}:presence")

    {:ok, lv1, html1} = live(log_in_user(conn, owner), ~p"/dashboard")
    refute html1 =~ member.email

    {:ok, lv2, _html2} = live(log_in_user(build_conn(), member), ~p"/dashboard")
    assert_receive %{event: "presence_diff"}, 1000

    assert render(lv1) =~ member.email
    assert render(lv2) =~ owner.email

    GenServer.stop(lv2.pid)
    assert_receive %{event: "presence_diff"}, 1000

    # The same presence_diff broadcast also has to reach lv1's own mailbox,
    # independently of ours — poll briefly rather than assuming delivery
    # order between two independent subscriber processes.
    refute still_shows?(lv1, member.email)
  end

  defp still_shows?(lv, text, attempts \\ 20)
  defp still_shows?(lv, text, 0), do: render(lv) =~ text

  defp still_shows?(lv, text, attempts) do
    if render(lv) =~ text do
      Process.sleep(10)
      still_shows?(lv, text, attempts - 1)
    else
      false
    end
  end
end
