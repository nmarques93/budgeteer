defmodule Budgeteer.EventsFixtures do
  @moduledoc """
  Test helpers for creating `Event` entities via `Budgeteer.Events`.
  """

  def event_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        title: "some title #{System.unique_integer()}",
        date: ~D[2026-08-15]
      })

    {:ok, event} = Budgeteer.Events.create_event(scope, attrs)
    event
  end
end
