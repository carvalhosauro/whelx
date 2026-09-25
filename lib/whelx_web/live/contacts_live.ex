defmodule WhelxWeb.ContactsLive do
  use WhelxWeb, :live_view
  import WhelxWeb.UI
  alias Whelx.{Contacts, Control, Events, Messaging}
  alias Whelx.Contacts.Contact

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe("config")
    {:ok, socket |> assign(page_title: "Contacts", errors: %{}) |> load()}
  end

  defp load(socket), do: assign(socket, contacts: Contacts.list_contacts())

  @impl true
  def handle_event("create", %{"contact" => params}, socket) do
    case Contacts.create_contact(Map.reject(params, fn {_k, v} -> v == "" end)) do
      {:ok, contact} ->
        {:noreply,
         socket
         |> assign(errors: %{})
         |> put_flash(:info, "Contact #{contact.profile_name} created")
         |> load()}

      {:error, cs} ->
        {:noreply, assign(socket, errors: Control.changeset_errors(cs))}
    end
  end

  def handle_event("bulk", %{"bulk" => %{"count" => count}}, socket) do
    case Integer.parse(count) do
      {n, _} ->
        case Contacts.bulk_create(n) do
          {:ok, n} -> {:noreply, socket |> put_flash(:info, "#{n} contacts generated") |> load()}
          {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "invalid count")}
    end
  end

  def handle_event("edit", %{"wa_id" => wa_id, "edit" => params}, socket) do
    with %Contact{} = contact <- Contacts.get_contact(wa_id),
         {:ok, _} <- Contacts.update_contact(contact, params) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "could not save")}
    end
  end

  def handle_event("toggle_online", %{"id" => wa_id}, socket) do
    contact = Contacts.get_contact(wa_id)
    {:ok, _} = Messaging.set_contact_online(contact, !contact.online)
    {:noreply, load(socket)}
  end

  def handle_event("delete", %{"id" => wa_id}, socket) do
    {:ok, _} = wa_id |> Contacts.get_contact() |> Contacts.delete_contact()
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info(_event, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:contacts}>
      <.page
        title="Contacts"
        subtitle="Fake WhatsApp users. Their behavior decides how the emulated Meta responds to sends."
      >
        <div class="mb-4 grid gap-4 md:grid-cols-2">
          <.panel title="New contact">
            <form id="contact-form" phx-submit="create" class="grid grid-cols-2 gap-2">
              <input
                name="contact[profile_name]"
                placeholder="Name (generated if empty)"
                class={input_class()}
              />
              <input
                name="contact[wa_id]"
                placeholder="5511999990000 (generated if empty)"
                class={input_class()}
              />
              <p :for={err <- Map.get(@errors, :wa_id, [])} class="col-span-2 text-xs text-red-600">
                wa_id {err}
              </p>
              <.btn type="submit" variant="primary" class="col-span-2">Create</.btn>
            </form>
          </.panel>
          <.panel title="Bulk generate (campaigns)">
            <form id="bulk-form" phx-submit="bulk" class="flex gap-2">
              <input
                type="number"
                name="bulk[count]"
                value="500"
                min="1"
                max="10000"
                class={input_class()}
              />
              <.btn type="submit">Generate</.btn>
            </form>
            <p class="mt-2 text-xs text-base-content/60">{length(@contacts)} contacts in total.</p>
          </.panel>
        </div>

        <.panel>
          <table class="w-full text-sm">
            <thead class="text-left text-xs uppercase text-base-content/60">
              <tr>
                <th class="py-2">Contact</th>
                <th>Behavior</th>
                <th>Read receipts</th>
                <th>Presence</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={c <- @contacts} class="border-t border-base-300">
                <td class="py-2">
                  <.link
                    navigate={~p"/?#{[contact: c.wa_id]}"}
                    class="font-medium hover:text-emerald-600"
                  >{c.profile_name}</.link>
                  <span class="block font-mono text-xs text-base-content/60">{c.wa_id}</span>
                </td>
                <td colspan="2">
                  <form id={"contact-#{c.wa_id}"} phx-change="edit" class="flex gap-2">
                    <input type="hidden" name="wa_id" value={c.wa_id} />
                    <select name="edit[behavior]" class={input_class()}>
                      {Phoenix.HTML.Form.options_for_select(
                        [
                          {"normal", "normal"},
                          {"invalid number (131026)", "invalid_number"},
                          {"blocked the business (131026)", "blocked"}
                        ],
                        c.behavior
                      )}
                    </select>
                    <select name="edit[read_policy]" class={input_class()}>
                      {Phoenix.HTML.Form.options_for_select(
                        [
                          {"reads on open", "on_open"},
                          {"reads automatically", "auto"},
                          {"never reads", "never"}
                        ],
                        c.read_policy
                      )}
                    </select>
                  </form>
                </td>
                <td>
                  <button phx-click="toggle_online" phx-value-id={c.wa_id}>
                    <.badge color={if c.online, do: "green", else: "gray"}>
                      {if c.online, do: "online", else: "offline"}
                    </.badge>
                  </button>
                </td>
                <td class="text-right">
                  <.btn variant="danger" phx-click="delete" phx-value-id={c.wa_id}>
                    <.icon name="hero-trash" class="size-4" />
                  </.btn>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@contacts == []} class="py-6 text-center text-sm text-base-content/60">
            No contacts yet.
          </p>
        </.panel>
      </.page>
    </Layouts.app>
    """
  end
end
