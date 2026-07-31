defmodule BudgeteerWeb.LocaleController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Households

  @known_locales ~w(en pt_PT)

  # A plain GET (not a LiveView event) — switching locale needs a full
  # reload anyway so every gettext() call re-resolves, so a plain link is
  # simpler than reinventing that over the live socket.
  def set(conn, %{"locale" => locale} = params) when locale in @known_locales do
    conn = put_session(conn, :locale, locale)

    case conn.assigns[:current_scope] do
      %{user: %Households.User{} = user} -> Households.update_user_locale(user, locale)
      _ -> :ok
    end

    redirect(conn, to: safe_return_to(params["return_to"]))
  end

  defp safe_return_to("/" <> _ = path) do
    if String.starts_with?(path, "//"), do: "/", else: path
  end

  defp safe_return_to(_path), do: "/"
end
