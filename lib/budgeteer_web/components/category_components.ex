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
    <span class={["inline-flex items-center gap-1.5", @class]}>
      <.icon name={@category.icon || "hero-tag"} class="size-4 text-primary" />
      {@category.name}
    </span>
    """
  end
end
