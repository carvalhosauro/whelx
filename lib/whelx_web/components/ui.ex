defmodule WhelxWeb.UI do
  @moduledoc "Small building blocks shared by whelx pages."
  use Phoenix.Component
  import WhelxWeb.CoreComponents, only: [icon: 1]
  alias Phoenix.LiveView.JS

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions
  slot :inner_block

  def page(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-6 md:px-8">
      <div class="mb-6 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">{@title}</h1>
          <p :if={@subtitle} class="mt-1 text-sm text-base-content/60">{@subtitle}</p>
        </div>
        <div class="flex flex-wrap gap-2">{render_slot(@actions)}</div>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, default: nil
  attr :class, :string, default: nil
  attr :id, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def panel(assigns) do
    ~H"""
    <section id={@id} class={["rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm", @class]}>
      <div :if={@title || @actions != []} class="mb-3 flex items-center justify-between gap-2">
        <h2 :if={@title} class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
          {@title}
        </h2>
        <div class="flex gap-2">{render_slot(@actions)}</div>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :color, :string, default: "gray"
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium",
      badge_color(@color),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_color("green"), do: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300"
  defp badge_color("red"), do: "bg-red-500/15 text-red-700 dark:text-red-300"
  defp badge_color("yellow"), do: "bg-amber-500/15 text-amber-700 dark:text-amber-300"
  defp badge_color("blue"), do: "bg-sky-500/15 text-sky-700 dark:text-sky-300"
  defp badge_color(_), do: "bg-base-300 text-base-content/70"

  attr :type, :string, default: "button"
  attr :variant, :string, default: "secondary"
  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(disabled form name value phx-click phx-value-id phx-disable-with)

  slot :inner_block, required: true

  def btn(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex items-center justify-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium transition active:scale-[0.98] disabled:opacity-50",
        btn_variant(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp btn_variant("primary"), do: "bg-emerald-600 text-white shadow-sm hover:bg-emerald-700"
  defp btn_variant("danger"), do: "text-red-600 hover:bg-red-500/10"
  defp btn_variant("ghost"), do: "text-base-content/70 hover:bg-base-200"
  defp btn_variant(_), do: "border border-base-300 bg-base-100 hover:bg-base-200"

  attr :text, :string, required: true
  attr :label, :string, default: "Copiar"

  def copy_button(assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs text-base-content/70 hover:bg-base-200"
      phx-click={JS.dispatch("whelx:copy", detail: %{text: @text})}
    >
      <.icon name="hero-clipboard-document" class="size-4" /> {@label}
    </button>
    """
  end

  attr :data, :any, required: true
  attr :class, :string, default: nil

  def json_block(assigns) do
    ~H"""
    <pre class={[
      "overflow-x-auto rounded-lg bg-base-200 p-3 font-mono text-xs leading-relaxed",
      @class
    ]}>{Jason.encode!(@data, pretty: true)}</pre>
    """
  end

  def input_class,
    do:
      "w-full rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 text-sm outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20"
end
