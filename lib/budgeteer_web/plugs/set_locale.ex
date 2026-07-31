defmodule BudgeteerWeb.Plugs.SetLocale do
  @moduledoc """
  Resolves which Gettext locale applies to this request and puts it in
  process state (`Gettext.put_locale/2`) so every `gettext/1`/`ngettext/3`
  call downstream — in this plug's own request, and later in a connected
  LiveView mount via `BudgeteerWeb.LocaleHook` — resolves correctly.

  Precedence: an explicit session override (set once by
  `LocaleController.set/2` when the switcher is clicked, and re-written on
  every request after that so it sticks) > the signed-in user's saved
  `locale` preference > the first recognized subtag in `Accept-Language` >
  `"en"`.
  """

  import Plug.Conn

  @known_locales ~w(en pt_PT)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = resolve_locale(conn)
    Gettext.put_locale(BudgeteerWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
    |> assign(:current_path, Phoenix.Controller.current_path(conn))
  end

  defp resolve_locale(conn) do
    with nil <- known(get_session(conn, :locale)),
         nil <- known(user_locale(conn)),
         nil <- accept_language_locale(conn) do
      "en"
    end
  end

  defp known(locale) when locale in @known_locales, do: locale
  defp known(_locale), do: nil

  defp user_locale(%Plug.Conn{assigns: %{current_scope: %{user: %{locale: locale}}}}),
    do: locale

  defp user_locale(_conn), do: nil

  # Not sorted by q-value — with only two supported locales, first-listed
  # match is close enough and avoids pulling in a header-parsing dependency.
  defp accept_language_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> case do
      nil -> nil
      header -> header |> String.split(",") |> Enum.find_value(&subtag_locale/1)
    end
  end

  defp subtag_locale(tag) do
    tag
    |> String.split(";")
    |> List.first()
    |> String.trim()
    |> String.split("-")
    |> List.first()
    |> String.downcase()
    |> known_language()
  end

  defp known_language("pt"), do: "pt_PT"
  defp known_language("en"), do: "en"
  defp known_language(_), do: nil
end
