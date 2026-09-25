defmodule WhelxWeb.LogsLive do
  use WhelxWeb, :live_view
  import WhelxWeb.UI
  alias Whelx.{Events, Logs, Webhooks}
  alias Whelx.Control.JSON

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe("requests")
      Events.subscribe("deliveries")
    end

    {:ok,
     socket
     |> assign(
       page_title: "Logs",
       tab: :requests,
       filter: "",
       selected: nil,
       refresh_scheduled: false
     )
     |> load()}
  end

  defp load(socket) do
    assign(socket,
      requests: Logs.list_requests(limit: 200, path: socket.assigns.filter),
      deliveries: Webhooks.list_deliveries(limit: 200)
    )
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket),
    do: {:noreply, assign(socket, tab: String.to_existing_atom(tab), selected: nil)}

  def handle_event("filter", %{"filter" => filter}, socket),
    do: {:noreply, socket |> assign(filter: filter) |> load()}

  def handle_event("select_request", %{"id" => id}, socket),
    do: {:noreply, assign(socket, selected: {:request, Logs.get_request(String.to_integer(id))})}

  def handle_event("select_delivery", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, selected: {:delivery, Webhooks.get_delivery(String.to_integer(id))})}

  def handle_event("redeliver", %{"id" => id}, socket) do
    {:ok, _} = Webhooks.redeliver(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Webhook reenfileirado") |> load()}
  end

  @impl true
  def handle_info(:refresh, socket),
    do: {:noreply, socket |> assign(refresh_scheduled: false) |> load()}

  def handle_info(_event, %{assigns: %{refresh_scheduled: true}} = socket), do: {:noreply, socket}

  def handle_info(_event, socket) do
    Process.send_after(self(), :refresh, 500)
    {:noreply, assign(socket, refresh_scheduled: true)}
  end

  defp status_color(status) when status in 200..299, do: "green"
  defp status_color(500), do: "red"
  defp status_color(_), do: "yellow"

  defp state_color("delivered"), do: "green"
  defp state_color(state) when state in ~w(failed dropped), do: "red"
  defp state_color(state) when state in ~w(retrying skipped merged), do: "yellow"
  defp state_color(_), do: "gray"

  defp decode(nil), do: nil

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, json} -> json
      _ -> body
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:logs}>
      <.page
        title="Logs"
        subtitle="Tudo que a sua aplicação chamou na Graph API fake e tudo que o whelx entregou por webhook."
      >
        <div class="mb-3 flex flex-wrap items-center gap-2">
          <.btn
            variant={if @tab == :requests, do: "primary", else: "secondary"}
            phx-click="tab"
            phx-value-tab="requests"
          >
            Graph API
          </.btn>
          <.btn
            variant={if @tab == :deliveries, do: "primary", else: "secondary"}
            phx-click="tab"
            phx-value-tab="deliveries"
          >
            Webhooks
          </.btn>
          <form :if={@tab == :requests} phx-change="filter" class="ml-auto" onsubmit="return false">
            <input
              name="filter"
              value={@filter}
              placeholder="Filtrar path"
              phx-debounce="200"
              class={input_class()}
            />
          </form>
        </div>

        <div class="grid gap-4 lg:grid-cols-[1fr_28rem]">
          <.panel class="overflow-x-auto">
            <table :if={@tab == :requests} class="w-full text-xs">
              <thead class="text-left uppercase text-base-content/60">
                <tr>
                  <th class="py-2">Hora</th><th>Método</th><th>Path</th><th>Status</th><th>ms</th><th>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={r <- @requests}
                  phx-click="select_request"
                  phx-value-id={r.id}
                  class={[
                    "cursor-pointer border-t border-base-300 hover:bg-base-200",
                    r.internal_error && "bg-red-500/10"
                  ]}
                >
                  <td class="py-1.5 font-mono">{Calendar.strftime(r.inserted_at, "%H:%M:%S")}</td>
                  <td class="font-semibold">{r.method}</td>
                  <td class="max-w-xs truncate font-mono">{r.path}</td>
                  <td>
                    <.badge color={status_color(r.response_status)}>{r.response_status}</.badge>
                  </td>
                  <td>{r.duration_ms}</td>
                  <td>
                    <.badge :if={r.chaos_tag} color="yellow">{r.chaos_tag}</.badge>
                    <.badge :if={r.internal_error} color="red">erro interno</.badge>
                  </td>
                </tr>
              </tbody>
            </table>

            <table :if={@tab == :deliveries} class="w-full text-xs">
              <thead class="text-left uppercase text-base-content/60">
                <tr>
                  <th class="py-2">#</th><th>Tipo</th><th>Estado</th><th>HTTP</th><th>Tent.</th><th>
                    wamid
                  </th><th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={d <- @deliveries} class="border-t border-base-300 hover:bg-base-200">
                  <td
                    class="cursor-pointer py-1.5 font-mono"
                    phx-click="select_delivery"
                    phx-value-id={d.id}
                  >
                    {d.id}
                  </td>
                  <td class="cursor-pointer" phx-click="select_delivery" phx-value-id={d.id}>
                    {d.kind}
                  </td>
                  <td>
                    <.badge color={state_color(d.state)}>{d.state}</.badge>
                    <.badge :if={d.chaos_tag} color="yellow">{d.chaos_tag}</.badge>
                  </td>
                  <td>{d.last_status}</td>
                  <td>{d.attempts}</td>
                  <td class="max-w-[10rem] truncate font-mono">{d.message_wamid}</td>
                  <td class="text-right">
                    <.btn variant="ghost" phx-click="redeliver" phx-value-id={d.id}>Reentregar</.btn>
                  </td>
                </tr>
              </tbody>
            </table>
          </.panel>

          <.panel title="Detalhe">
            <%= case @selected do %>
              <% {:request, r} when not is_nil(r) -> %>
                <p class="mb-2 font-mono text-xs">
                  {r.method} {r.path}{if r.query, do: "?" <> r.query}
                </p>
                <p class="mb-1 text-xs font-semibold">Headers</p>
                <.json_block data={r.request_headers} />
                <p class="mb-1 mt-3 text-xs font-semibold">Request</p>
                <.json_block data={decode(r.request_body)} class="max-h-72" />
                <p class="mb-1 mt-3 text-xs font-semibold">Response {r.response_status}</p>
                <.json_block data={decode(r.response_body)} class="max-h-72" />
              <% {:delivery, d} when not is_nil(d) -> %>
                <p :if={d.last_error} class="mb-2 text-xs text-red-600">{d.last_error}</p>
                <p class="mb-1 text-xs font-semibold">X-Hub-Signature-256</p>
                <p class="mb-3 break-all font-mono text-[11px]">{d.signature || "—"}</p>
                <.json_block data={JSON.delivery(d)} class="max-h-[32rem]" />
              <% _ -> %>
                <p class="text-sm text-base-content/60">Clique numa linha para ver o JSON.</p>
            <% end %>
          </.panel>
        </div>
      </.page>
    </Layouts.app>
    """
  end
end
