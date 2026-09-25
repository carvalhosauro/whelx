defmodule WhelxWeb.ChaosLive do
  use WhelxWeb, :live_view
  import WhelxWeb.UI
  alias Whelx.{Chaos, Control}

  @rates [
    {:sync_error_rate, "Erro síncrono na Graph API",
     "130429 em /messages, 131000, HTTP 500, 503"},
    {:async_fail_rate, "Falha assíncrona (status failed)", "códigos async_fail_codes"},
    {:reorder_rate, "Reordenar status", "entrega um status 2 s depois do próximo"},
    {:duplicate_rate, "Duplicar webhook", "testa idempotência por wamid"},
    {:drop_rate, "Perder webhook", "evento nunca é entregue"},
    {:batch_rate, "Agrupar status", "vários statuses num POST só"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Caos", rates: @rates) |> load()}
  end

  defp load(socket), do: assign(socket, profile: Chaos.get_profile())

  @impl true
  def handle_event("preset", %{"name" => name}, socket) do
    {:ok, _} = Chaos.apply_preset(name)
    {:noreply, socket |> put_flash(:info, "Preset #{name} aplicado") |> load()}
  end

  def handle_event("save", %{"chaos" => params}, socket) do
    params =
      params
      |> Map.update("sync_error_codes", nil, &split_list/1)
      |> Map.update("async_fail_codes", nil, fn v ->
        v |> split_list() |> Enum.map(&String.to_integer/1)
      end)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.put("preset", "custom")

    case Chaos.update_profile(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Caos salvo") |> load()}
      {:error, cs} -> {:noreply, put_flash(socket, :error, inspect(Control.changeset_errors(cs)))}
    end
  rescue
    ArgumentError -> {:noreply, put_flash(socket, :error, "async_fail_codes deve conter números")}
  end

  defp split_list(value), do: value |> String.split([",", " "], trim: true)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:chaos}>
      <.page
        title="Caos"
        subtitle="Falhas determinísticas por seed: mesma seed + mesma sequência = mesmo resultado."
      >
        <:actions>
          <.btn
            :for={name <- Chaos.presets()}
            variant={if @profile.preset == name, do: "primary", else: "secondary"}
            phx-click="preset"
            phx-value-name={name}
          >
            {name}
          </.btn>
        </:actions>

        <.panel>
          <form id="chaos-form" phx-submit="save" class="space-y-4 text-sm">
            <div class="grid gap-3 md:grid-cols-3">
              <label>
                <span class="mb-1 block text-base-content/70">Seed</span>
                <input type="number" name="chaos[seed]" value={@profile.seed} class={input_class()} />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Latência mínima (ms)</span>
                <input
                  type="number"
                  name="chaos[latency_min_ms]"
                  value={@profile.latency_min_ms}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Latência máxima (ms)</span>
                <input
                  type="number"
                  name="chaos[latency_max_ms]"
                  value={@profile.latency_max_ms}
                  class={input_class()}
                />
              </label>
            </div>

            <div class="grid gap-3 md:grid-cols-2">
              <label
                :for={{field, label, hint} <- @rates}
                class="rounded-lg border border-base-300 p-3"
              >
                <span class="flex items-center justify-between">
                  <span class="font-medium">{label}</span>
                  <span class="font-mono text-xs">{round(Map.fetch!(@profile, field) * 100)}%</span>
                </span>
                <span class="mb-2 block text-xs text-base-content/60">{hint}</span>
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.01"
                  name={"chaos[#{field}]"}
                  value={Map.fetch!(@profile, field)}
                  class="w-full accent-emerald-600"
                />
              </label>
            </div>

            <div class="grid gap-3 md:grid-cols-3">
              <label>
                <span class="mb-1 block text-base-content/70">Códigos síncronos</span>
                <input
                  name="chaos[sync_error_codes]"
                  value={Enum.join(@profile.sync_error_codes, ", ")}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Códigos assíncronos</span>
                <input
                  name="chaos[async_fail_codes]"
                  value={Enum.join(@profile.async_fail_codes, ", ")}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Atraso extra de webhook (ms)</span>
                <input
                  type="number"
                  name="chaos[webhook_extra_delay_ms]"
                  value={@profile.webhook_extra_delay_ms}
                  class={input_class()}
                />
              </label>
            </div>

            <.btn type="submit" variant="primary">Salvar</.btn>
          </form>
        </.panel>
      </.page>
    </Layouts.app>
    """
  end
end
