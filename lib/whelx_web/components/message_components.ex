defmodule WhelxWeb.MessageComponents do
  @moduledoc "WhatsApp-like rendering of messages, from the contact's point of view."
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: WhelxWeb.Endpoint, router: WhelxWeb.Router
  import WhelxWeb.CoreComponents, only: [icon: 1]
  alias Phoenix.LiveView.JS
  alias Whelx.Messaging.Message

  @reactions ~w(👍 ❤️ 😂 🙏)

  attr :message, Message, required: true
  attr :selected, :boolean, default: false

  def bubble(assigns) do
    assigns =
      assign(assigns,
        content: Message.content(assigns.message),
        mine: assigns.message.direction == "inbound",
        reactions: @reactions
      )

    ~H"""
    <div id={"msg-#{@message.id}"} class={["group flex", @mine && "justify-end"]}>
      <div class="max-w-[80%] md:max-w-md">
        <div
          phx-click="inspect"
          phx-value-wamid={@message.wamid}
          class={[
            "relative cursor-pointer rounded-xl px-3 py-2 text-sm shadow-sm transition",
            @mine &&
              "rounded-tr-sm bg-emerald-100 text-emerald-950 dark:bg-emerald-900/60 dark:text-emerald-50",
            !@mine && "rounded-tl-sm bg-base-100",
            @selected && "ring-2 ring-sky-400"
          ]}
        >
          <div
            :if={@message.context_wamid && @message.type != "reaction"}
            class="mb-1 truncate rounded border-l-4 border-emerald-500 bg-black/5 px-2 py-1 text-xs opacity-70"
          >
            ↩ resposta a {String.slice(@message.context_wamid, 0, 18)}…
          </div>
          <.body type={@message.type} content={@content} message={@message} />
          <div class="mt-1 flex items-center justify-end gap-1.5 text-[10px] opacity-60">
            <span :if={@message.chaos_tag} class="rounded bg-amber-400/30 px-1">{@message.chaos_tag}</span>
            <span :if={!@mine} class={status_class(@message.status)}>{@message.status}</span>
            <span>{Calendar.strftime(@message.inserted_at, "%H:%M:%S")}</span>
            <.ticks :if={@mine} status={@message.status} />
          </div>
        </div>
        <div :if={!@mine} class="mt-0.5 flex gap-0.5 opacity-0 transition group-hover:opacity-100">
          <button
            :for={emoji <- @reactions}
            type="button"
            phx-click="react"
            phx-value-wamid={@message.wamid}
            phx-value-emoji={emoji}
            class="rounded-full px-1 text-sm hover:bg-base-300"
          >
            {emoji}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :content, :map, required: true
  attr :message, Message, required: true

  defp body(%{type: "text"} = assigns) do
    ~H"""
    <p class="whitespace-pre-wrap break-words">{@content["body"]}</p>
    """
  end

  defp body(%{type: "interactive", content: %{"type" => reply_type}} = assigns)
       when reply_type in ~w(button_reply list_reply) do
    assigns = assign(assigns, reply: assigns.content[reply_type])

    ~H"""
    <p class="font-medium">{@reply["title"]}</p>
    <p :if={@reply["description"]} class="text-xs opacity-70">{@reply["description"]}</p>
    <p class="mt-0.5 font-mono text-[10px] opacity-50">
      {String.replace(@content["type"], "_", " ")} · id {@reply["id"]}
    </p>
    """
  end

  defp body(%{type: "button"} = assigns) do
    ~H"""
    <p class="font-medium">{@content["text"]}</p>
    <p class="mt-0.5 font-mono text-[10px] opacity-50">quick reply · payload {@content["payload"]}</p>
    """
  end

  defp body(%{type: "interactive", content: %{"type" => "button"}} = assigns) do
    ~H"""
    <.interactive_header content={@content} />
    <p class="whitespace-pre-wrap break-words">{get_in(@content, ["body", "text"])}</p>
    <p :if={get_in(@content, ["footer", "text"])} class="mt-1 text-xs opacity-60">
      {get_in(@content, ["footer", "text"])}
    </p>
    <div class="mt-2 grid gap-1 border-t border-black/10 pt-2">
      <.reply_button
        :for={b <- get_in(@content, ["action", "buttons"]) || []}
        wamid={@message.wamid}
        id={b["reply"]["id"]}
      >
        {b["reply"]["title"]}
      </.reply_button>
    </div>
    """
  end

  defp body(%{type: "interactive", content: %{"type" => "list"}} = assigns) do
    ~H"""
    <.interactive_header content={@content} />
    <p class="whitespace-pre-wrap break-words">{get_in(@content, ["body", "text"])}</p>
    <details class="mt-2 border-t border-black/10 pt-2">
      <summary class="cursor-pointer list-none text-center font-medium text-sky-600">
        <.icon name="hero-list-bullet" class="size-4" /> {get_in(@content, ["action", "button"])}
      </summary>
      <div :for={section <- get_in(@content, ["action", "sections"]) || []} class="mt-2">
        <p :if={section["title"]} class="mb-1 text-xs font-semibold uppercase opacity-60">
          {section["title"]}
        </p>
        <.reply_button
          :for={row <- section["rows"] || []}
          wamid={@message.wamid}
          id={row["id"]}
          align="left"
        >
          <span class="block">{row["title"]}</span>
          <span :if={row["description"]} class="block text-xs opacity-60">{row["description"]}</span>
        </.reply_button>
      </div>
    </details>
    """
  end

  defp body(%{type: "interactive", content: %{"type" => "cta_url"}} = assigns) do
    ~H"""
    <.interactive_header content={@content} />
    <p class="whitespace-pre-wrap break-words">{get_in(@content, ["body", "text"])}</p>
    <a
      href={get_in(@content, ["action", "parameters", "url"])}
      target="_blank"
      rel="noopener"
      class="mt-2 flex items-center justify-center gap-1 border-t border-black/10 pt-2 font-medium text-sky-600"
    >
      <.icon name="hero-arrow-top-right-on-square" class="size-4" />
      {get_in(@content, ["action", "parameters", "display_text"])}
    </a>
    """
  end

  defp body(%{type: "interactive", content: %{"type" => "order_details"}} = assigns) do
    params = get_in(assigns.content, ["action", "parameters"]) || %{}
    order = params["order"] || %{}
    pix = Enum.find_value(params["payment_settings"] || [], & &1["pix_dynamic_code"])
    assigns = assign(assigns, params: params, order: order, pix: pix)

    ~H"""
    <p class="whitespace-pre-wrap break-words">{get_in(@content, ["body", "text"])}</p>
    <div class="mt-2 min-w-60 rounded-lg bg-black/5 p-2 text-xs">
      <p class="mb-1 font-semibold">Pedido {@params["reference_id"]}</p>
      <div :for={item <- @order["items"] || []} class="flex justify-between gap-2">
        <span>{item["quantity"]}× {item["name"]}</span>
        <span>{money(item["sale_amount"] || item["amount"])}</span>
      </div>
      <div
        :if={@order["subtotal"]}
        class="mt-1 flex justify-between border-t border-black/10 pt-1 opacity-70"
      >
        <span>Subtotal</span><span>{money(@order["subtotal"])}</span>
      </div>
      <div
        :for={key <- ~w(tax shipping discount)}
        :if={@order[key]}
        class="flex justify-between opacity-70"
      >
        <span>{@order[key]["description"] || key}</span>
        <span>{if key == "discount", do: "−"}{money(@order[key])}</span>
      </div>
      <div class="mt-1 flex justify-between border-t border-black/10 pt-1 text-sm font-semibold">
        <span>Total</span><span>{money(@params["total_amount"])}</span>
      </div>
    </div>
    <button
      :if={@pix}
      type="button"
      phx-click={JS.dispatch("whelx:copy", detail: %{text: @pix["code"]})}
      class="mt-2 w-full rounded-lg bg-emerald-600 py-1.5 text-center text-xs font-semibold text-white hover:bg-emerald-700"
    >
      Copiar código Pix
    </button>
    """
  end

  defp body(%{type: "template"} = assigns) do
    assigns = assign(assigns, rendered: assigns.message.payload["rendered"] || %{})

    ~H"""
    <div :if={@rendered["header"]} class="mb-1 font-semibold">
      <%= case @rendered["header"] do %>
        <% %{"format" => "TEXT", "text" => text} -> %>
          {text}
        <% %{"format" => format} = header -> %>
          <span class="flex items-center gap-1 text-xs opacity-70">
            <.icon name="hero-photo" class="size-4" /> {format} {header["link"] || header["id"]}
          </span>
      <% end %>
    </div>
    <p class="whitespace-pre-wrap break-words">
      {@rendered["body"] || "template #{@content["name"]}"}
    </p>
    <p :if={@rendered["footer"]} class="mt-1 text-xs opacity-60">{@rendered["footer"]}</p>
    <div
      :if={(@rendered["buttons"] || []) != []}
      class="mt-2 grid gap-1 border-t border-black/10 pt-2"
    >
      <%= for b <- @rendered["buttons"] do %>
        <.reply_button :if={b["type"] == "QUICK_REPLY"} wamid={@message.wamid} id={b["index"]}>{b[
          "text"
        ]}</.reply_button>
        <a
          :if={b["type"] == "URL"}
          href={b["url"]}
          target="_blank"
          rel="noopener"
          class="text-center font-medium text-sky-600"
        >{b["text"]}</a>
        <span :if={b["type"] not in ~w(QUICK_REPLY URL)} class="text-center opacity-60">{b["text"] ||
          b["type"]}</span>
      <% end %>
    </div>
    <p class="mt-1 text-[10px] uppercase opacity-50">
      template · {@content["name"]} · {@content["language"]["code"]}
    </p>
    """
  end

  defp body(%{type: "image"} = assigns) do
    ~H"""
    <img
      src={~p"/ui/media/#{@content["id"]}"}
      class="max-h-64 rounded-lg"
      alt={@content["caption"] || "imagem"}
    />
    <p :if={@content["caption"]} class="mt-1">{@content["caption"]}</p>
    """
  end

  defp body(%{type: "audio"} = assigns) do
    ~H"""
    <audio controls src={~p"/ui/media/#{@content["id"]}"} class="h-10 max-w-full"></audio>
    <p class="text-[10px] opacity-60">
      {if @content["voice"], do: "🎤 mensagem de voz", else: "áudio"} · {@content["mime_type"]}
    </p>
    """
  end

  defp body(%{type: type} = assigns) when type in ~w(video document sticker) do
    ~H"""
    <a
      href={~p"/ui/media/#{@content["id"]}"}
      target="_blank"
      class="flex items-center gap-2 font-medium text-sky-600"
    >
      <.icon name="hero-paper-clip" class="size-4" /> {@content["filename"] || @type} · {@content[
        "mime_type"
      ]}
    </a>
    <p :if={@content["caption"]} class="mt-1">{@content["caption"]}</p>
    """
  end

  defp body(%{type: "location"} = assigns) do
    ~H"""
    <a
      href={"https://www.openstreetmap.org/?mlat=#{@content["latitude"]}&mlon=#{@content["longitude"]}"}
      target="_blank"
      class="block"
    >
      <span class="flex items-center gap-1 font-medium"><.icon name="hero-map-pin" class="size-4" /> {@content[
        "name"
      ] || "Localização"}</span>
      <span class="block text-xs opacity-70">{@content["address"]}</span>
      <span class="block font-mono text-[10px] opacity-60">{@content["latitude"]}, {@content[
        "longitude"
      ]}</span>
    </a>
    """
  end

  defp body(%{type: "reaction"} = assigns) do
    ~H"""
    <p>
      reagiu {@content["emoji"] || "(removida)"} a {String.slice(@content["message_id"] || "", 0, 18)}…
    </p>
    """
  end

  defp body(assigns) do
    ~H"""
    <pre class="overflow-x-auto text-xs">{Jason.encode!(@content, pretty: true)}</pre>
    """
  end

  attr :content, :map, required: true

  defp interactive_header(assigns) do
    ~H"""
    <p :if={get_in(@content, ["header", "text"])} class="mb-1 font-semibold">
      {get_in(@content, ["header", "text"])}
    </p>
    """
  end

  attr :wamid, :string, required: true
  attr :id, :string, required: true
  attr :align, :string, default: "center"
  slot :inner_block, required: true

  defp reply_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="reply"
      phx-value-wamid={@wamid}
      phx-value-id={@id}
      class={[
        "w-full rounded-md px-2 py-1 font-medium text-sky-600 transition hover:bg-sky-500/10",
        @align == "left" && "text-left",
        @align == "center" && "text-center"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :status, :string, required: true

  def ticks(assigns) do
    ~H"""
    <span class={[@status == "read" && "text-sky-500"]} title={@status}>
      {if @status == "read", do: "✓✓", else: "✓"}
    </span>
    """
  end

  defp status_class("failed"), do: "font-semibold text-red-600"
  defp status_class("read"), do: "text-sky-600"
  defp status_class(_), do: nil

  @doc "Formats a Meta amount object (`value` in cents, `offset` 100) as BRL."
  def money(%{"value" => value, "offset" => offset}) when is_integer(value) and offset > 0 do
    reais = div(value, offset)
    cents = rem(value, offset) |> Integer.to_string() |> String.pad_leading(2, "0")

    whole =
      reais
      |> Integer.to_string()
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(".", &Enum.join/1)
      |> String.reverse()

    "R$ #{whole},#{cents}"
  end

  def money(_), do: "—"
end
