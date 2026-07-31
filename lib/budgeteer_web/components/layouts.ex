defmodule BudgeteerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BudgeteerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :online_members, :list, default: [], doc: "other household members currently connected"

  attr :container_class, :string,
    default: "max-w-2xl",
    doc:
      "override for pages that need more width than the default reading-width column (e.g. a calendar grid)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div :if={@online_members != []} class="flex flex-wrap gap-1 px-4 pt-4 sm:px-6 lg:px-8">
      <span :for={member <- @online_members} class="badge badge-success badge-outline gap-1">
        <span class="size-2 rounded-full bg-success"></span> {member.name || member.email} online
      </span>
    </div>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class={["mx-auto space-y-4", @container_class]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
