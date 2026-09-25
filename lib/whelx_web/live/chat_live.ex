defmodule WhelxWeb.ChatLive do
  @moduledoc "WhatsApp-like chat where you play the customer."
  use WhelxWeb, :live_view
  import WhelxWeb.UI
  import WhelxWeb.MessageComponents
  alias Whelx.{Accounts, Contacts, Control, Events, Messaging, Webhooks}

  @refresh_ms 300

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe("messages")
      Events.subscribe("conversations")
      Events.subscribe("config")
      :timer.send_interval(1_000, :tick)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Chat",
       phones: Accounts.list_all_phone_numbers(),
       phone: nil,
       conversation: nil,
       messages: [],
       inspected: nil,
       deliveries: [],
       refresh_scheduled: false,
       search: "",
       now: DateTime.utc_now(),
       form: to_form(%{"text" => ""}, as: :msg)
     )
     |> allow_upload(:media,
       accept: :any,
       max_entries: 1,
       max_file_size: 16_000_000
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    phone = pick_phone(socket.assigns.phones, params["phone"])
    socket = assign(socket, phone: phone, inspected: nil, deliveries: [])

    socket =
      case {phone, params["contact"]} do
        {nil, _} ->
          assign(socket, conversation: nil, messages: [])

        {_phone, blank} when blank in [nil, ""] ->
          assign(socket, conversation: nil, messages: [])

        {phone, wa_id} ->
          contact = Contacts.find_or_create_contact(wa_id)
          conversation = Messaging.get_or_create_conversation(phone.id, contact.wa_id)
          open(socket, conversation.id)
      end

    {:noreply, load_sidebar(socket)}
  end

  defp pick_phone([], _id), do: nil
  defp pick_phone(phones, id), do: Enum.find(phones, &(&1.id == id)) || hd(phones)

  defp open(socket, conversation_id) do
    :ok = Messaging.open_conversation(conversation_id)
    reload_conversation(socket, conversation_id)
  end

  defp reload_conversation(socket, conversation_id) do
    conversation = Messaging.get_conversation!(conversation_id)
    assign(socket, conversation: conversation, messages: conversation.messages)
  end

  defp load_sidebar(%{assigns: %{phone: nil}} = socket), do: assign(socket, rows: [])

  defp load_sidebar(socket) do
    phone = socket.assigns.phone
    conversations = Map.new(Messaging.list_conversations(phone.id), &{&1.contact_wa_id, &1})
    last = conversations |> Map.values() |> Enum.map(& &1.id) |> Messaging.last_messages()
    search = String.downcase(socket.assigns.search)

    rows =
      Contacts.list_contacts()
      |> Enum.filter(
        &(search == "" or
            String.contains?(String.downcase(&1.profile_name <> " " <> &1.wa_id), search))
      )
      |> Enum.map(fn contact ->
        conversation = conversations[contact.wa_id]

        %{
          contact: contact,
          conversation: conversation,
          last: conversation && last[conversation.id]
        }
      end)
      |> Enum.sort_by(
        fn row -> row.conversation && row.conversation.last_message_at end,
        &sort_desc/2
      )

    assign(socket, rows: rows)
  end

  defp sort_desc(nil, _), do: false
  defp sort_desc(_, nil), do: true
  defp sort_desc(a, b), do: DateTime.compare(a, b) != :lt

  # Events

  @impl true
  def handle_event("select_phone", %{"phone" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/?#{[phone: id]}")}

  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, socket |> assign(search: q) |> load_sidebar()}

  def handle_event("send", %{"msg" => %{"text" => text}}, socket) do
    if String.trim(text) == "" do
      {:noreply, socket}
    else
      socket
      |> as_contact(%{"type" => "text", "text" => text})
      |> then(&{:noreply, assign(&1, form: to_form(%{"text" => ""}, as: :msg))})
    end
  end

  def handle_event("reply", %{"wamid" => wamid, "id" => id}, socket) do
    case Control.reply_interactive(socket.assigns.conversation.contact_wa_id, wamid, id) do
      {:ok, _} -> {:noreply, refresh_now(socket)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("react", %{"wamid" => wamid, "emoji" => emoji}, socket),
    do:
      {:noreply,
       as_contact(socket, %{"type" => "reaction", "message_id" => wamid, "emoji" => emoji})}

  def handle_event("send_location", %{"loc" => loc}, socket) do
    attrs = %{
      "type" => "location",
      "latitude" => to_float(loc["latitude"]),
      "longitude" => to_float(loc["longitude"]),
      "name" => blank_to_nil(loc["name"]),
      "address" => blank_to_nil(loc["address"])
    }

    {:noreply, as_contact(socket, attrs)}
  end

  def handle_event("audio_recorded", %{"data" => data, "mime" => mime}, socket),
    do:
      {:noreply,
       as_contact(socket, %{
         "type" => "audio",
         "media_base64" => data,
         "mime_type" => normalize_mime(mime)
       })}

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("upload_media", params, socket) do
    caption = blank_to_nil(params["caption"])

    results =
      consume_uploaded_entries(socket, :media, fn %{path: path}, entry ->
        {:ok, {File.read!(path), entry.client_type, entry.client_name}}
      end)

    socket =
      Enum.reduce(results, socket, fn {binary, mime, name}, acc ->
        type = media_type(mime)
        conversation = acc.assigns.conversation

        {:ok, _} =
          Messaging.receive_inbound_media(
            conversation.phone_number_id,
            conversation.contact_wa_id,
            type,
            binary,
            mime,
            caption: caption,
            file_name: name
          )

        acc
      end)

    {:noreply, refresh_now(socket)}
  end

  def handle_event("inspect", %{"wamid" => wamid}, socket) do
    message = Enum.find(socket.assigns.messages, &(&1.wamid == wamid))

    {:noreply,
     assign(socket,
       inspected: message,
       deliveries: Webhooks.list_deliveries(message_wamid: wamid)
     )}
  end

  def handle_event("close_inspect", _params, socket),
    do: {:noreply, assign(socket, inspected: nil, deliveries: [])}

  def handle_event("expire_window", _params, socket) do
    {:ok, _} = Messaging.expire_window(socket.assigns.conversation)
    {:noreply, refresh_now(socket)}
  end

  def handle_event("toggle_online", _params, socket) do
    contact = socket.assigns.conversation.contact
    {:ok, _} = Messaging.set_contact_online(contact, !contact.online)
    {:noreply, refresh_now(socket)}
  end

  defp as_contact(socket, attrs) do
    conversation = socket.assigns.conversation
    attrs = Map.put(attrs, "phone_number_id", conversation.phone_number_id)

    case Control.send_as_contact(conversation.contact_wa_id, attrs) do
      {:ok, _} -> refresh_now(socket)
      {:error, reason} -> put_flash(socket, :error, error_text(reason))
    end
  end

  # PubSub

  @impl true
  def handle_info({event, message}, socket) when event in [:message_created, :message_updated] do
    socket =
      case socket.assigns.conversation do
        %{id: id} when id == message.conversation_id ->
          if event == :message_updated and message.direction == "inbound",
            do: reload_conversation(socket, id),
            else: open(socket, id)

        _ ->
          socket
      end

    {:noreply, schedule_refresh(socket)}
  end

  def handle_info({:conversation_updated, id}, socket) do
    socket =
      case socket.assigns.conversation do
        %{id: ^id} -> reload_conversation(socket, id)
        _ -> socket
      end

    {:noreply, schedule_refresh(socket)}
  end

  def handle_info(:refresh, socket),
    do: {:noreply, socket |> assign(refresh_scheduled: false) |> load_sidebar()}

  def handle_info(:tick, socket), do: {:noreply, assign(socket, now: DateTime.utc_now())}

  def handle_info(:reset, socket), do: {:noreply, push_navigate(socket, to: ~p"/")}

  def handle_info(_event, socket) do
    {:noreply, socket |> assign(phones: Accounts.list_all_phone_numbers()) |> schedule_refresh()}
  end

  defp schedule_refresh(%{assigns: %{refresh_scheduled: true}} = socket), do: socket

  defp schedule_refresh(socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    assign(socket, refresh_scheduled: true)
  end

  defp refresh_now(%{assigns: %{conversation: %{id: id}}} = socket),
    do: socket |> reload_conversation(id) |> load_sidebar()

  defp refresh_now(socket), do: load_sidebar(socket)

  # Helpers

  defp media_type("image/" <> _), do: "image"
  defp media_type("audio/" <> _), do: "audio"
  defp media_type("video/" <> _), do: "video"
  defp media_type(_), do: "document"

  defp normalize_mime(mime),
    do:
      mime
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

  defp to_float(value) do
    case Float.parse(to_string(value)) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason), do: inspect(reason)

  defp window_label(conversation, now) do
    if Messaging.window_open?(conversation, now) do
      minutes = DateTime.diff(conversation.window_expires_at, now, :minute)

      {:open,
       "Window open · closes in #{div(minutes, 60)}h#{String.pad_leading("#{rem(minutes, 60)}", 2, "0")}"}
    else
      {:closed, "Window closed · templates only"}
    end
  end

  defp typing?(%{typing_until: %DateTime{} = until}, now), do: DateTime.after?(until, now)
  defp typing?(_conversation, _now), do: false

  defp preview(nil), do: "no messages"

  defp preview(%{type: "text"} = m),
    do: arrow(m) <> (Whelx.Messaging.Message.content(m)["body"] || "")

  defp preview(%{type: "template"} = m),
    do: arrow(m) <> "📄 " <> (m.payload["rendered"]["body"] || "template")

  defp preview(m), do: arrow(m) <> "[#{m.type}]"

  defp arrow(%{direction: "outbound"}), do: "← "
  defp arrow(_), do: "→ "

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:chat}>
      <div class="flex h-screen">
        <aside class="flex w-72 shrink-0 flex-col border-r border-base-300 bg-base-100">
          <div class="space-y-2 border-b border-base-300 p-3">
            <form id="phone-select" phx-change="select_phone">
              <select name="phone" class={input_class()} disabled={@phones == []}>
                <option :if={@phones == []}>No phone numbers — see Config</option>
                <option :for={p <- @phones} value={p.id} selected={@phone && p.id == @phone.id}>
                  {p.verified_name} · {p.display_phone_number}
                </option>
              </select>
            </form>
            <form id="contact-search" phx-change="search" onsubmit="return false">
              <input
                name="q"
                value={@search}
                placeholder="Search contacts"
                phx-debounce="200"
                class={input_class()}
              />
            </form>
          </div>
          <div class="min-h-0 flex-1 overflow-y-auto">
            <.link
              :for={row <- @rows}
              patch={~p"/?#{[phone: @phone.id, contact: row.contact.wa_id]}"}
              class={[
                "flex items-center gap-3 border-b border-base-200 px-3 py-2.5 transition hover:bg-base-200",
                @conversation && @conversation.contact_wa_id == row.contact.wa_id &&
                  "bg-emerald-500/10"
              ]}
            >
              <div class="relative grid size-10 shrink-0 place-items-center rounded-full bg-emerald-600/15 font-semibold text-emerald-700 dark:text-emerald-300">
                {String.first(row.contact.profile_name)}
                <span
                  :if={row.contact.online}
                  class="absolute bottom-0 right-0 size-2.5 rounded-full border-2 border-base-100 bg-emerald-500"
                ></span>
              </div>
              <div class="min-w-0 flex-1">
                <div class="flex items-center justify-between gap-2">
                  <span class="truncate text-sm font-medium">{row.contact.profile_name}</span>
                  <span
                    :if={row.conversation && row.conversation.unread_count > 0}
                    class="rounded-full bg-emerald-600 px-1.5 text-[10px] font-bold text-white"
                  >
                    {row.conversation.unread_count}
                  </span>
                </div>
                <p class="truncate text-xs text-base-content/60">{preview(row.last)}</p>
              </div>
            </.link>
            <div :if={@rows == []} class="p-6 text-center text-sm text-base-content/60">
              No contacts yet.
              <.link navigate={~p"/contacts"} class="text-emerald-600 underline">Create contacts</.link>
            </div>
          </div>
        </aside>

        <section class="flex min-w-0 flex-1 flex-col bg-[#efeae2] dark:bg-base-300">
          <%= if @conversation do %>
            <header class="flex flex-wrap items-center gap-3 border-b border-base-300 bg-base-100 px-4 py-2.5">
              <div class="min-w-0">
                <p class="truncate font-semibold">{@conversation.contact.profile_name}</p>
                <p class="font-mono text-xs text-base-content/60">
                  +{@conversation.contact.wa_id}
                  <span
                    :if={typing?(@conversation, @now)}
                    class="ml-2 font-sans italic text-emerald-600"
                  >typing…</span>
                </p>
              </div>
              <% {state, label} = window_label(@conversation, @now) %>
              <.badge color={if state == :open, do: "green", else: "yellow"}>{label}</.badge>
              <.badge :if={@conversation.contact.behavior != "normal"} color="red">
                {@conversation.contact.behavior}
              </.badge>
              <div class="ml-auto flex gap-1">
                <.btn variant="ghost" phx-click="toggle_online">
                  {if @conversation.contact.online, do: "Go offline", else: "Go online"}
                </.btn>
                <.btn variant="ghost" phx-click="expire_window">Expire window</.btn>
              </div>
            </header>

            <div class="flex min-h-0 flex-1">
              <div
                id="messages"
                phx-hook=".ScrollBottom"
                class="min-h-0 flex-1 space-y-2 overflow-y-auto px-4 py-4 md:px-8"
              >
                <.bubble
                  :for={m <- @messages}
                  message={m}
                  selected={@inspected && @inspected.id == m.id}
                />
                <p :if={@messages == []} class="mt-10 text-center text-sm text-base-content/60">
                  No messages yet. Send a "hi" to open the 24h window.
                </p>
              </div>

              <aside
                :if={@inspected}
                class="w-96 shrink-0 overflow-y-auto border-l border-base-300 bg-base-100 p-4"
              >
                <div class="mb-3 flex items-center justify-between">
                  <h3 class="text-sm font-semibold">Message</h3>
                  <button phx-click="close_inspect" class="rounded p-1 hover:bg-base-200"><.icon
                    name="hero-x-mark"
                    class="size-4"
                  /></button>
                </div>
                <p class="mb-2 break-all font-mono text-xs">{@inspected.wamid}</p>
                <.json_block data={Whelx.Control.JSON.message(@inspected)} class="max-h-72" />
                <h3 class="mb-2 mt-4 text-sm font-semibold">Webhooks ({length(@deliveries)})</h3>
                <div :for={d <- @deliveries} class="mb-3 rounded-lg border border-base-300 p-2">
                  <div class="mb-1 flex flex-wrap items-center gap-1 text-xs">
                    <.badge color={delivery_color(d.state)}>{d.state}</.badge>
                    <span>{d.kind}</span>
                    <span :if={d.last_status} class="font-mono">HTTP {d.last_status}</span>
                    <span :if={d.chaos_tag} class="text-amber-600">{d.chaos_tag}</span>
                    <span class="ml-auto opacity-60">#{d.id} · {d.attempts} attempt(s)</span>
                  </div>
                  <p :if={d.last_error} class="mb-1 text-xs text-red-600">{d.last_error}</p>
                  <.json_block data={d.payload} class="max-h-60" />
                </div>
              </aside>
            </div>

            <footer class="border-t border-base-300 bg-base-100 px-3 py-2">
              <div class="flex items-end gap-2">
                <details class="relative">
                  <summary
                    class="grid size-9 cursor-pointer list-none place-items-center rounded-full hover:bg-base-200"
                    title="Attach"
                  >
                    <.icon name="hero-paper-clip" class="size-5" />
                  </summary>
                  <div class="absolute bottom-11 left-0 z-10 w-80 space-y-3 rounded-xl border border-base-300 bg-base-100 p-3 shadow-lg">
                    <form
                      id="upload-form"
                      phx-submit="upload_media"
                      phx-change="validate_upload"
                      class="space-y-2"
                    >
                      <p class="text-xs font-semibold uppercase text-base-content/60">File</p>
                      <.live_file_input upload={@uploads.media} class="block w-full text-xs" />
                      <input name="caption" placeholder="Caption (optional)" class={input_class()} />
                      <p :for={entry <- @uploads.media.entries} class="text-xs">
                        {entry.client_name} · {entry.progress}%
                        <span :for={err <- upload_errors(@uploads.media, entry)} class="text-red-600">{inspect(
                          err
                        )}</span>
                      </p>
                      <.btn type="submit" class="w-full">Send file</.btn>
                    </form>
                    <form id="location-form" phx-submit="send_location" class="grid grid-cols-2 gap-2">
                      <p class="col-span-2 text-xs font-semibold uppercase text-base-content/60">
                        Location
                      </p>
                      <input
                        name="loc[latitude]"
                        value="-23.5614"
                        placeholder="Latitude"
                        class={input_class()}
                      />
                      <input
                        name="loc[longitude]"
                        value="-46.6559"
                        placeholder="Longitude"
                        class={input_class()}
                      />
                      <input
                        name="loc[name]"
                        placeholder="Name"
                        class={"col-span-2 " <> input_class()}
                      />
                      <input
                        name="loc[address]"
                        placeholder="Address"
                        class={"col-span-2 " <> input_class()}
                      />
                      <.btn type="submit" class="col-span-2">Send location</.btn>
                    </form>
                  </div>
                </details>

                <.form for={@form} id="composer" phx-submit="send" class="flex flex-1 items-end gap-2">
                  <input
                    name="msg[text]"
                    value={@form[:text].value}
                    placeholder="Message as the customer"
                    autocomplete="off"
                    class="min-h-9 flex-1 rounded-full border border-base-300 bg-base-200 px-4 py-2 text-sm outline-none focus:border-emerald-500"
                  />
                  <button
                    type="submit"
                    class="grid size-9 place-items-center rounded-full bg-emerald-600 text-white hover:bg-emerald-700"
                    title="Send"
                  >
                    <.icon name="hero-paper-airplane" class="size-5" />
                  </button>
                </.form>

                <button
                  id="audio-recorder"
                  type="button"
                  phx-hook=".AudioRecorder"
                  class="grid size-9 place-items-center rounded-full hover:bg-base-200 data-[recording]:animate-pulse data-[recording]:bg-red-500 data-[recording]:text-white"
                  title="Hold to record audio"
                >
                  <.icon name="hero-microphone" class="size-5" />
                </button>
              </div>
            </footer>
          <% else %>
            <div class="grid flex-1 place-items-center p-8 text-center">
              <div>
                <p class="text-lg font-semibold">Pick a contact</p>
                <p class="mt-1 text-sm text-base-content/60">
                  You chat as the customer. Replies come from your application through the emulated Graph API.
                </p>
              </div>
            </div>
          <% end %>
        </section>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollBottom">
        export default {
          mounted() { this.el.scrollTop = this.el.scrollHeight },
          updated() {
            const nearBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 200
            if (nearBottom) this.el.scrollTop = this.el.scrollHeight
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AudioRecorder">
        export default {
          mounted() {
            const start = async () => {
              if (this.recorder) return
              try {
                const stream = await navigator.mediaDevices.getUserMedia({audio: true})
                const mime = ["audio/ogg;codecs=opus", "audio/webm;codecs=opus"].find(t => MediaRecorder.isTypeSupported(t)) || ""
                const chunks = []
                this.recorder = new MediaRecorder(stream, mime ? {mimeType: mime} : {})
                this.recorder.ondataavailable = e => chunks.push(e.data)
                this.recorder.onstop = async () => {
                  stream.getTracks().forEach(t => t.stop())
                  const blob = new Blob(chunks, {type: this.recorder.mimeType})
                  const buffer = new Uint8Array(await blob.arrayBuffer())
                  let binary = ""
                  buffer.forEach(b => binary += String.fromCharCode(b))
                  this.pushEvent("audio_recorded", {data: btoa(binary), mime: this.recorder.mimeType || "audio/webm"})
                  this.recorder = null
                  delete this.el.dataset.recording
                }
                this.recorder.start()
                this.el.dataset.recording = ""
              } catch (err) {
                alert("Could not record audio: " + err.message)
              }
            }
            const stop = () => this.recorder && this.recorder.state === "recording" && this.recorder.stop()
            this.el.addEventListener("pointerdown", start)
            this.el.addEventListener("pointerup", stop)
            this.el.addEventListener("pointerleave", stop)
          }
        }
      </script>
    </Layouts.app>
    """
  end

  defp delivery_color("delivered"), do: "green"
  defp delivery_color(state) when state in ~w(failed dropped), do: "red"
  defp delivery_color(state) when state in ~w(retrying skipped), do: "yellow"
  defp delivery_color(_), do: "gray"
end
