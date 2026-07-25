defmodule BudgeteerWeb.PageController do
  use BudgeteerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
