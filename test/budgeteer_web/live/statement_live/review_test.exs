defmodule BudgeteerWeb.StatementLive.ReviewTest do
  use BudgeteerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Budgeteer.Ledger
  alias Budgeteer.Statements

  import Budgeteer.LedgerFixtures, only: [account_fixture: 1, category_fixture: 2]
  import Budgeteer.StatementsFixtures

  setup :register_and_log_in_user

  defp create_account(%{scope: scope}) do
    %{account: account_fixture(scope)}
  end

  defp processed_statement_fixture(scope, account, raw_ai_output) do
    statement = statement_fixture(scope, %{account: account})
    {:ok, statement} = Statements.mark_processed(statement, raw_ai_output)
    statement
  end

  describe "Review" do
    setup [:create_account]

    test "renders one row per extracted transaction, pre-filled, with category matched case-insensitively",
         %{
           conn: conn,
           scope: scope,
           account: account
         } do
      category = category_fixture(scope, %{name: "Groceries"})

      raw_ai_output = %{
        "currency" => "EUR",
        "transactions" => [
          %{
            "date" => "2026-07-20",
            "amount_cents" => -4250,
            "merchant" => "Continente",
            "description" => "Weekly shop",
            "category" => "groceries"
          },
          %{
            "date" => "2026-07-21",
            "amount_cents" => -1200,
            "merchant" => "Corner Cafe",
            "description" => "Coffee",
            "category" => "Restaurants"
          }
        ]
      }

      statement = processed_statement_fixture(scope, account, raw_ai_output)

      {:ok, review_live, html} =
        live(conn, ~p"/accounts/#{account}/statements/#{statement}/review")

      assert html =~ "Review #{statement.filename}"
      assert html =~ "Continente"
      assert html =~ "-42.50"
      assert html =~ "Weekly shop"
      assert html =~ "Corner Cafe"
      assert html =~ "-12.00"

      # "groceries" matches the existing "Groceries" category case-insensitively -> pre-selected
      assert has_element?(review_live, ~s{option[value="#{category.id}"][selected]})

      # "Restaurants" has no existing match -> shown as a "Suggested:" hint instead
      assert html =~ "Suggested:"
      assert html =~ "Restaurants"
    end

    test "creating a suggested category assigns it to every matching row", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      raw_ai_output = %{
        "currency" => "EUR",
        "transactions" => [
          %{
            "date" => "2026-07-20",
            "amount_cents" => -1200,
            "merchant" => "Corner Cafe",
            "description" => "Coffee",
            "category" => "Restaurants"
          },
          %{
            "date" => "2026-07-21",
            "amount_cents" => -1500,
            "merchant" => "Pizza Place",
            "description" => "Dinner",
            "category" => "restaurants"
          }
        ]
      }

      statement = processed_statement_fixture(scope, account, raw_ai_output)

      {:ok, review_live, _html} =
        live(conn, ~p"/accounts/#{account}/statements/#{statement}/review")

      html =
        review_live
        |> element(~s{button[phx-value-index="0"]}, "Create it")
        |> render_click()

      assert html =~ "Created category"
      refute html =~ "Suggested:"

      assert [%Budgeteer.Ledger.Category{name: "Restaurants", type: :expense}] =
               Ledger.list_categories(scope)

      # both rows (case-insensitive match) got assigned, not just the one clicked
      assert has_element?(
               review_live,
               ~s{select[name="rows[0][category_id]"] option[selected]},
               "Restaurants"
             )

      assert has_element?(
               review_live,
               ~s{select[name="rows[1][category_id]"] option[selected]},
               "Restaurants"
             )
    end

    test "shows a successful balance reconciliation", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      statement =
        processed_statement_fixture(scope, account, %{
          "currency" => "EUR",
          "statement_period" => %{"from" => "2026-07-01", "to" => "2026-07-31"},
          "opening_balance_cents" => 10_000,
          "closing_balance_cents" => 8_800,
          "transactions" => [
            %{
              "date" => "2026-07-20",
              "amount_cents" => -1_200,
              "merchant" => "Market",
              "description" => "Shopping",
              "category" => ""
            }
          ]
        })

      {:ok, review_live, _html} =
        live(conn, ~p"/accounts/#{account}/statements/#{statement}/review")

      assert has_element?(review_live, "#balance-reconciliation")
      assert render(review_live) =~ "reconciles"
    end

    test "shows a balance mismatch warning", %{conn: conn, scope: scope, account: account} do
      statement =
        processed_statement_fixture(scope, account, %{
          "currency" => "EUR",
          "opening_balance_cents" => 10_000,
          "closing_balance_cents" => 9_000,
          "transactions" => [
            %{
              "date" => "2026-07-20",
              "amount_cents" => -1_200,
              "merchant" => "Market",
              "description" => "Shopping",
              "category" => ""
            }
          ]
        })

      {:ok, review_live, _html} =
        live(conn, ~p"/accounts/#{account}/statements/#{statement}/review")

      assert has_element?(review_live, "#balance-reconciliation")
      assert render(review_live) =~ "Balance mismatch"
    end

    test "flags an extracted row that already exists in the account", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      transaction_fixture = %{
        account_id: account.id,
        date: ~D[2026-07-20],
        amount: "-42.50",
        merchant: "Continente",
        description: "Weekly shop"
      }

      {:ok, _transaction} = Ledger.create_transaction(scope, transaction_fixture)

      statement =
        processed_statement_fixture(scope, account, %{
          "currency" => "EUR",
          "transactions" => [
            %{
              "date" => "2026-07-20",
              "amount_cents" => -4250,
              "merchant" => "Continente",
              "description" => "Weekly shop",
              "category" => ""
            }
          ]
        })

      {:ok, review_live, html} =
        live(conn, ~p"/accounts/#{account}/statements/#{statement}/review")

      assert html =~ "duplicate"
      assert has_element?(review_live, "#review-warnings")
      refute has_element?(review_live, ~s{input[name="rows[0][include]"][value="true"][checked]})
    end

    test "flags incomplete extracted rows and leaves them unchecked", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      statement =
        processed_statement_fixture(scope, account, %{
          "currency" => "EUR",
          "transactions" => [
            %{
              "date" => "",
              "amount_cents" => 0,
              "merchant" => "",
              "description" => "",
              "category" => ""
            }
          ]
        })

      {:ok, review_live, html} =
        live(conn, ~p"/accounts/#{account}/statements/#{statement}/review")

      assert html =~ "incomplete"
      refute has_element?(review_live, ~s{input[name="rows[0][include]"][value="true"][checked]})
    end

    test "shows a message and no form when the statement hasn't been processed yet", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      statement = statement_fixture(scope, %{account: account})

      {:ok, _review_live, html} =
        live(conn, ~p"/accounts/#{account}/statements/#{statement}/review")

      assert html =~ "isn&#39;t ready to review yet"
      refute html =~ "review-form"
    end

    test "submitting saves only the checked rows as transactions", %{
      conn: conn,
      scope: scope,
      account: account
    } do
      raw_ai_output = %{
        "currency" => "EUR",
        "transactions" => [
          %{
            "date" => "2026-07-20",
            "amount_cents" => -4250,
            "merchant" => "Continente",
            "description" => "Weekly shop",
            "category" => ""
          },
          %{
            "date" => "2026-07-21",
            "amount_cents" => -1200,
            "merchant" => "Corner Cafe",
            "description" => "Coffee",
            "category" => ""
          }
        ]
      }

      statement = processed_statement_fixture(scope, account, raw_ai_output)

      {:ok, review_live, _html} =
        live(conn, ~p"/accounts/#{account}/statements/#{statement}/review")

      params = %{
        "rows" => %{
          "0" => %{
            "include" => "true",
            "date" => "2026-07-20",
            "amount" => "-42.50",
            "merchant" => "Continente",
            "description" => "Weekly shop",
            "category_id" => ""
          },
          "1" => %{
            "include" => "false",
            "date" => "2026-07-21",
            "amount" => "-12.00",
            "merchant" => "Corner Cafe",
            "description" => "Coffee",
            "category_id" => ""
          }
        }
      }

      assert {:ok, _index_live, html} =
               review_live
               |> render_submit("save", params)
               |> follow_redirect(conn, ~p"/accounts/#{account}/transactions")

      assert html =~ "1 transaction saved"

      assert [transaction] = Ledger.list_transactions(scope)
      assert transaction.merchant == "Continente"
      assert transaction.statement_id == statement.id

      # raw_ai_output is a temporary staging artifact, not a permanent
      # record — once reviewed, keeping an indefinite encrypted copy of
      # the statement's contents only widens what a future key
      # compromise would expose, for no benefit.
      assert Statements.get_statement!(scope, statement.id).raw_ai_output == nil
    end
  end
end
