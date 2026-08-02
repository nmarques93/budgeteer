defmodule BudgeteerWeb.InboundEmailControllerTest do
  use BudgeteerWeb.ConnCase

  import Mox
  import Budgeteer.HouseholdsFixtures, only: [household_scope_fixture: 0]
  import Budgeteer.LedgerFixtures, only: [account_fixture: 1]

  alias Budgeteer.Statements

  setup :verify_on_exit!

  # Matches config/test.exs's fixed test-only value.
  @secret "whsec_dGVzdC1zZWNyZXQta2V5LWZvci1zaWduaW5n"

  defp webhook_payload(to, attachments) do
    Jason.encode!(%{
      "type" => "email.received",
      "data" => %{
        "email_id" => "email_test123",
        "from" => "bank@example.com",
        "to" => [to],
        "subject" => "Your monthly statement",
        "attachments" => attachments
      }
    })
  end

  defp signed_conn(conn, body) do
    id = "msg_#{System.unique_integer([:positive])}"
    timestamp = Integer.to_string(System.system_time(:second))
    key = @secret |> String.replace_prefix("whsec_", "") |> Base.decode64!()
    signature = :hmac |> :crypto.mac(:sha256, key, "#{id}.#{timestamp}.#{body}") |> Base.encode64()

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("svix-id", id)
    |> put_req_header("svix-timestamp", timestamp)
    |> put_req_header("svix-signature", "v1,#{signature}")
  end

  describe "POST /webhooks/resend-inbound" do
    test "with a valid signature, matching account, and real attachment, creates a statement", %{
      conn: conn
    } do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      to = "stmt-#{account.inbound_email_token}@inbound.test"

      body =
        webhook_payload(to, [
          %{"id" => "att_1", "filename" => "statement.pdf", "content_type" => "application/pdf"}
        ])

      expect(Budgeteer.Statements.ResendInboundClientMock, :fetch_attachment, fn "email_test123",
                                                                                  "att_1" ->
        {:ok, %{filename: "statement.pdf", content_type: "application/pdf", bytes: "%PDF-fake"}}
      end)

      expect(Budgeteer.AI.ClientMock, :parse_statement, fn _bytes,
                                                           "application/pdf",
                                                           _category_names ->
        {:ok, %{"currency" => "EUR", "transactions" => []}}
      end)

      conn = conn |> signed_conn(body) |> post(~p"/webhooks/resend-inbound", body)

      assert conn.status == 200
      assert [statement] = Statements.list_statements(scope, account)
      assert statement.filename == "statement.pdf"
      assert is_nil(statement.uploaded_by_id)
    end

    test "with an invalid signature, responds 401 and creates nothing", %{conn: conn} do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      to = "stmt-#{account.inbound_email_token}@inbound.test"

      body =
        webhook_payload(to, [
          %{"id" => "att_1", "filename" => "statement.pdf", "content_type" => "application/pdf"}
        ])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("svix-id", "msg_bad")
        |> put_req_header("svix-timestamp", Integer.to_string(System.system_time(:second)))
        |> put_req_header("svix-signature", "v1,not-a-real-signature")
        |> post(~p"/webhooks/resend-inbound", body)

      assert conn.status == 401
      assert Statements.list_statements(scope, account) == []
    end

    test "a valid signature for an unrecognized address still responds 200, creates nothing", %{
      conn: conn
    } do
      body =
        webhook_payload("stmt-no-such-token@inbound.test", [
          %{"id" => "att_1", "filename" => "statement.pdf", "content_type" => "application/pdf"}
        ])

      conn = conn |> signed_conn(body) |> post(~p"/webhooks/resend-inbound", body)

      assert conn.status == 200
    end

    test "an attachment with a disallowed extension is skipped, not saved", %{conn: conn} do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      to = "stmt-#{account.inbound_email_token}@inbound.test"

      body =
        webhook_payload(to, [
          %{"id" => "att_1", "filename" => "not-a-statement.exe", "content_type" => "text/plain"}
        ])

      conn = conn |> signed_conn(body) |> post(~p"/webhooks/resend-inbound", body)

      assert conn.status == 200
      assert Statements.list_statements(scope, account) == []
    end

    test "an attachment whose content doesn't match its claimed extension is skipped", %{
      conn: conn
    } do
      scope = household_scope_fixture()
      account = account_fixture(scope)
      to = "stmt-#{account.inbound_email_token}@inbound.test"

      body =
        webhook_payload(to, [
          %{"id" => "att_1", "filename" => "statement.pdf", "content_type" => "application/pdf"}
        ])

      expect(Budgeteer.Statements.ResendInboundClientMock, :fetch_attachment, fn _email_id,
                                                                                  _attachment_id ->
        {:ok,
         %{filename: "statement.pdf", content_type: "application/pdf", bytes: "not really a pdf"}}
      end)

      conn = conn |> signed_conn(body) |> post(~p"/webhooks/resend-inbound", body)

      assert conn.status == 200
      assert Statements.list_statements(scope, account) == []
    end
  end
end
