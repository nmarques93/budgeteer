defmodule BudgeteerWeb.PresenceHooks do
  @moduledoc """
  Tracks the current user's presence on the household's presence topic and
  keeps `@online_members` (everyone else currently connected) up to date.

  Wired into the router's authenticated `live_session` as a second
  `on_mount` entry, so no individual LiveView needs its own tracking code
  or a `handle_info` clause for presence_diff — the `attach_hook` below
  absorbs those messages before they reach the LiveView module.
  """

  import Phoenix.LiveView, only: [connected?: 1, attach_hook: 4]
  import Phoenix.Component, only: [assign: 3, assign_new: 3]

  alias BudgeteerWeb.Presence

  def on_mount(:track, _params, _session, socket) do
    current_scope = socket.assigns[:current_scope]

    if connected?(socket) && current_scope && current_scope.user do
      user = current_scope.user
      topic = presence_topic(user.household_id)

      {:ok, _ref} = Presence.track(self(), topic, user.id, %{email: user.email, name: user.name})
      Phoenix.PubSub.subscribe(Budgeteer.PubSub, topic)

      socket =
        socket
        |> assign(:online_members, list_online_members(topic, user.id))
        |> attach_hook(:presence_updates, :handle_info, &handle_presence_diff(&1, &2, topic, user.id))

      {:cont, socket}
    else
      {:cont, assign_new(socket, :online_members, fn -> [] end)}
    end
  end

  defp handle_presence_diff(%{topic: msg_topic, event: "presence_diff"}, socket, topic, user_id)
       when msg_topic == topic do
    {:halt, assign(socket, :online_members, list_online_members(topic, user_id))}
  end

  defp handle_presence_diff(_msg, socket, _topic, _user_id), do: {:cont, socket}

  defp list_online_members(topic, exclude_user_id) do
    topic
    |> Presence.list()
    |> Enum.reject(fn {user_id, _} -> user_id == exclude_user_id end)
    |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
      %{id: user_id, email: meta.email, name: meta.name}
    end)
  end

  defp presence_topic(household_id), do: "household:#{household_id}:presence"
end
