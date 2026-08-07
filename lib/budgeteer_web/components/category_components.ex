defmodule BudgeteerWeb.CategoryComponents do
  use Phoenix.Component
  use Gettext, backend: BudgeteerWeb.Gettext

  import BudgeteerWeb.CoreComponents

  attr :category, :any, default: nil
  attr :class, :any, default: nil

  def category_badge(%{category: nil} = assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1.5 opacity-70", @class]}>
      <.icon name="hero-tag" class="size-4" />
      {gettext("Uncategorized")}
    </span>
    """
  end

  def category_badge(assigns) do
    ~H"""
    <span
      class={["inline-flex items-center gap-1.5", @class]}
      style={category_color_style(@category.color)}
    >
      <.icon name={@category.icon || "hero-tag"} class="size-4" />
      {@category.name}
    </span>
    """
  end

  defp category_color_style("#" <> hex = color) when byte_size(hex) == 6 do
    if Regex.match?(~r/^[0-9a-fA-F]{6}$/, hex), do: "color: #{color};"
  end

  defp category_color_style(_color), do: nil
end
