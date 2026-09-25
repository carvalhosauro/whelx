defmodule WhelxWeb.CampaignsLive do
  use WhelxWeb, :live_view
  import WhelxWeb.UI
  alias Whelx.{Logs, Messaging}

  @windows [{"5 min", 300}, {"1 hora", 3600}, {"24 horas", 86_400}]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, :tick)
    {:ok, socket |> assign(page_title: "Campanhas", window: 3600, windows: @windows) |> load()}
  end

  defp load(socket) do
    since = DateTime.add(DateTime.utc_now(), -socket.assigns.window, :second)

    stats =
      since
      |> Messaging.campaign_stats()
      |> Enum.map(fn s ->
        seconds =
          if s.first_at && s.last_at,
            do: max(DateTime.diff(s.last_at, s.first_at, :millisecond), 1) / 1000,
            else: 1

        Map.put(s, :rate, if(s.total > 1, do: Float.round(s.total / seconds, 1), else: s.total))
      end)

    assign(socket, stats: stats, rate_limited: Logs.count_rate_limited(since))
  end

  @impl true
  def handle_event("window", %{"window" => window}, socket),
    do: {:noreply, socket |> assign(window: String.to_integer(window)) |> load()}

  @impl true
  def handle_info(:tick, socket), do: {:noreply, load(socket)}

  defp pct(_part, 0), do: 0
  defp pct(part, total), do: round(part * 100 / total)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:campaigns}>
      <.page title="Campanhas" subtitle="Envios de template agrupados por nome. Atualiza a cada 2 s.">
        <:actions>
          <form phx-change="window">
            <select name="window" class={input_class()}>
              {Phoenix.HTML.Form.options_for_select(
                Enum.map(@windows, fn {l, v} -> {l, v} end),
                @window
              )}
            </select>
          </form>
        </:actions>

        <div class="mb-4 grid grid-cols-2 gap-4 md:grid-cols-4">
          <.panel>
            <p class="text-xs uppercase text-base-content/60">Templates enviados</p>
            <p class="text-2xl font-bold">{Enum.sum(Enum.map(@stats, & &1.total))}</p>
          </.panel>
          <.panel>
            <p class="text-xs uppercase text-base-content/60">Falhas</p>
            <p class="text-2xl font-bold text-red-600">{Enum.sum(Enum.map(@stats, & &1.failed))}</p>
          </.panel>
          <.panel>
            <p class="text-xs uppercase text-base-content/60">130429 (rate limit)</p>
            <p class="text-2xl font-bold text-amber-600">{@rate_limited}</p>
          </.panel>
          <.panel>
            <p class="text-xs uppercase text-base-content/60">Templates distintos</p>
            <p class="text-2xl font-bold">{length(@stats)}</p>
          </.panel>
        </div>

        <.panel>
          <table class="w-full text-sm">
            <thead class="text-left text-xs uppercase text-base-content/60">
              <tr>
                <th class="py-2">Template</th><th>Total</th><th>msg/s</th><th class="w-1/3">
                  Status
                </th><th>accepted</th><th>sent</th><th>delivered</th><th>read</th><th>failed</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={s <- @stats} class="border-t border-base-300">
                <td class="py-2 font-medium">{s.name}</td>
                <td>{s.total}</td>
                <td>{s.rate}</td>
                <td>
                  <div class="flex h-2 overflow-hidden rounded-full bg-base-300">
                    <div class="bg-base-content/30" style={"width: #{pct(s.accepted, s.total)}%"}>
                    </div>
                    <div class="bg-sky-300" style={"width: #{pct(s.sent, s.total)}%"}></div>
                    <div class="bg-emerald-400" style={"width: #{pct(s.delivered, s.total)}%"}></div>
                    <div class="bg-sky-600" style={"width: #{pct(s.read, s.total)}%"}></div>
                    <div class="bg-red-500" style={"width: #{pct(s.failed, s.total)}%"}></div>
                  </div>
                </td>
                <td>{s.accepted}</td>
                <td>{s.sent}</td>
                <td>{s.delivered}</td>
                <td>{s.read}</td>
                <td class="text-red-600">{s.failed}</td>
              </tr>
            </tbody>
          </table>
          <p :if={@stats == []} class="py-6 text-center text-sm text-base-content/60">
            Nenhum envio de template nessa janela. Dispare uma campanha pela sua aplicação.
          </p>
        </.panel>
      </.page>
    </Layouts.app>
    """
  end
end
