defmodule WhelxWeb.ChaosLive do
  use WhelxWeb, :live_view
  import WhelxWeb.UI
  alias Whelx.{Chaos, Control}

  @rates [
    {:sync_error_rate, "Synchronous Graph API error",
     "130429 on /messages, 131000, HTTP 500, 503"},
    {:async_fail_rate, "Asynchronous failure (failed status)", "async_fail_codes codes"},
    {:reorder_rate, "Reorder statuses", "delivers a status 2 s after the next one"},
    {:duplicate_rate, "Duplicate webhook", "tests idempotency by wamid"},
    {:drop_rate, "Drop webhook", "event is never delivered"},
    {:batch_rate, "Batch statuses", "several statuses in a single POST"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Chaos", rates: @rates) |> load()}
  end

  defp load(socket), do: assign(socket, profile: Chaos.get_profile())

  @impl true
  def handle_event("preset", %{"name" => name}, socket) do
    {:ok, _} = Chaos.apply_preset(name)
    {:noreply, socket |> put_flash(:info, "Preset #{name} applied") |> load()}
  end

  def handle_event("save", %{"chaos" => params}, socket) do
    params =
      params
      |> Map.update("sync_error_codes", nil, &split_list/1)
      |> Map.update("async_fail_codes", nil, fn v ->
        v |> split_list() |> Enum.map(&String.to_integer/1)
      end)
      |> Map.update("phone_number_ids", nil, &split_list/1)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.put("preset", "custom")

    case Chaos.update_profile(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Chaos saved") |> load()}
      {:error, cs} -> {:noreply, put_flash(socket, :error, inspect(Control.changeset_errors(cs)))}
    end
  rescue
    ArgumentError ->
      {:noreply, put_flash(socket, :error, "async_fail_codes must contain numbers")}
  end

  defp split_list(value), do: value |> String.split([",", " "], trim: true)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:chaos}>
      <.page
        title="Chaos"
        subtitle="Deterministic, seeded failures: same seed + same sequence = same outcome."
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
                <span class="mb-1 block text-base-content/70">Min latency (ms)</span>
                <input
                  type="number"
                  name="chaos[latency_min_ms]"
                  value={@profile.latency_min_ms}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Max latency (ms)</span>
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
                <span class="mb-1 block text-base-content/70">Sync error codes</span>
                <input
                  name="chaos[sync_error_codes]"
                  value={Enum.join(@profile.sync_error_codes, ", ")}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Async failure codes</span>
                <input
                  name="chaos[async_fail_codes]"
                  value={Enum.join(@profile.async_fail_codes, ", ")}
                  class={input_class()}
                />
              </label>
              <label class="md:col-span-3">
                <span class="mb-1 block text-base-content/70">Only these phone_number_ids (empty = all)</span>
                <input
                  name="chaos[phone_number_ids]"
                  value={Enum.join(@profile.phone_number_ids || [], ", ")}
                  placeholder="e.g. 219000000009101"
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Extra webhook delay (ms)</span>
                <input
                  type="number"
                  name="chaos[webhook_extra_delay_ms]"
                  value={@profile.webhook_extra_delay_ms}
                  class={input_class()}
                />
              </label>
            </div>

            <.btn type="submit" variant="primary">Save</.btn>
          </form>
        </.panel>
      </.page>
    </Layouts.app>
    """
  end
end
