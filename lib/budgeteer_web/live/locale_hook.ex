defmodule BudgeteerWeb.LocaleHook do
  @moduledoc """
  Re-applies the request's resolved locale inside the LiveView process.

  Gettext's locale is per-process, and a connected LiveView mount runs in a
  different process than the one `BudgeteerWeb.Plugs.SetLocale` ran in for
  the initial HTTP request — without this, every `gettext/1` call in a
  LiveView would silently fall back to the default locale on the connected
  (post-JS) mount, even though the disconnected render was correct.

  Wired into every `live_session`'s `on_mount` list in the router, same
  convention as `BudgeteerWeb.PresenceHooks`.
  """

  def on_mount(:default, _params, session, socket) do
    locale = session["locale"] || "en"
    Gettext.put_locale(BudgeteerWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
