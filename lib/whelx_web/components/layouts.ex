defmodule WhelxWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use WhelxWeb, :html

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

  attr :active, :atom, default: nil, doc: "active navigation entry"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex h-screen overflow-hidden bg-base-200 text-base-content">
      <nav class="flex w-16 shrink-0 flex-col items-center gap-1 border-r border-base-300 bg-base-100 py-3 md:w-48 md:items-stretch md:px-2">
        <.link navigate={~p"/"} class="mb-3 flex items-center gap-2 px-2">
          <span class="grid size-8 place-items-center rounded-lg bg-emerald-600 font-black text-white">w</span>
          <span class="hidden text-lg font-bold tracking-tight md:inline">whelx</span>
        </.link>
        <.nav_item navigate={~p"/"} icon="hero-chat-bubble-left-right" active={@active == :chat}>
          Chat
        </.nav_item>
        <.nav_item navigate={~p"/contacts"} icon="hero-users" active={@active == :contacts}>
          Contacts
        </.nav_item>
        <.nav_item navigate={~p"/templates"} icon="hero-document-text" active={@active == :templates}>
          Templates
        </.nav_item>
        <.nav_item navigate={~p"/campaigns"} icon="hero-megaphone" active={@active == :campaigns}>
          Campaigns
        </.nav_item>
        <.nav_item navigate={~p"/logs"} icon="hero-queue-list" active={@active == :logs}>
          Logs
        </.nav_item>
        <.nav_item navigate={~p"/chaos"} icon="hero-bolt" active={@active == :chaos}>Chaos</.nav_item>
        <.nav_item navigate={~p"/config"} icon="hero-cog-6-tooth" active={@active == :config}>
          Config
        </.nav_item>
        <div class="mt-auto flex justify-center pt-3"><.theme_toggle /></div>
      </nav>
      <main class="min-w-0 flex-1 overflow-y-auto">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      title={render_slot(@inner_block)}
      class={[
        "flex items-center gap-3 rounded-lg px-2 py-2 text-sm transition-colors",
        @active && "bg-emerald-600/15 font-semibold text-emerald-700 dark:text-emerald-400",
        !@active && "text-base-content/70 hover:bg-base-200 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-5 shrink-0" />
      <span class="hidden md:inline">{render_slot(@inner_block)}</span>
    </.link>
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

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
