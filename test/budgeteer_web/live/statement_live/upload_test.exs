defmodule BudgeteerWeb.StatementLive.UploadTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Budgeteer.LedgerFixtures, only: [account_fixture: 1]

  setup :register_and_log_in_user

  defp create_account(%{scope: scope}) do
    %{account: account_fixture(scope)}
  end

  describe "Upload" do
    setup [:create_account]

    test "mounts for a valid account_id", %{conn: conn, account: account} do
      {:ok, _upload_live, html} = live(conn, ~p"/accounts/#{account}/statements/new")

      assert html =~ "Upload statement"
      assert html =~ "For #{account.name}"
    end

    test "renders a plain multipart form posting to the statements controller", %{conn: conn, account: account} do
      {:ok, upload_live, _html} = live(conn, ~p"/accounts/#{account}/statements/new")

      # Not a LiveView allow_upload — a real HTML form POST (see
      # BudgeteerWeb.StatementController and CLAUDE.md for why), so submission
      # itself is covered by StatementControllerTest, not here.
      assert has_element?(upload_live, ~s{form[action="/accounts/#{account.id}/statements"][enctype="multipart/form-data"]})
      assert has_element?(upload_live, ~s{input[type="file"][name="statement[file]"]})
    end
  end
end
