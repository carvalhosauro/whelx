defmodule WhelxWeb.ConfigLive do
  use WhelxWeb, :live_view
  import WhelxWeb.UI
  alias Whelx.{Accounts, Control, Events, Webhooks}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe("config")

    {:ok,
     socket
     |> assign(page_title: "Config", reveal_secret: false, verify_result: nil, app_errors: %{})
     |> load()}
  end

  defp load(socket) do
    app = Accounts.get_app!()
    settings = Accounts.get_settings()

    assign(socket,
      app: app,
      settings: settings,
      wabas: Enum.map(Accounts.list_wabas(), &{&1, Accounts.list_phone_numbers(&1.id)}),
      tokens: Accounts.list_tokens(),
      env_block: Control.env_block(),
      app_form:
        to_form(%{"webhook_url" => app.webhook_url, "verify_token" => app.verify_token}, as: :app),
      settings_form:
        to_form(
          Map.new(
            ~w(webhook_retry_profile template_approval_policy template_review_after_ms template_reject_reason sent_delay_ms delivered_delay_ms pair_rate_limit_enabled pair_rate_limit_burst pair_rate_limit_interval_ms)a,
            &{Atom.to_string(&1), Map.fetch!(settings, &1)}
          ),
          as: :settings
        )
    )
  end

  @impl true
  def handle_event("save_app", %{"app" => params}, socket) do
    case Accounts.upsert_app(params) do
      {:ok, _} ->
        {:noreply, socket |> assign(app_errors: %{}) |> put_flash(:info, "App salvo") |> load()}

      {:error, cs} ->
        {:noreply, assign(socket, app_errors: Control.changeset_errors(cs))}
    end
  end

  def handle_event("toggle_secret", _params, socket),
    do: {:noreply, update(socket, :reveal_secret, &(!&1))}

  def handle_event("regenerate_secret", _params, socket) do
    {:ok, _} = Accounts.regenerate_app_secret()

    {:noreply,
     socket
     |> put_flash(:info, "App secret regenerado — atualize o app secret na sua aplicação")
     |> load()}
  end

  def handle_event("verify", _params, socket) do
    result =
      case Webhooks.verify() do
        {:ok, %{ok: true}} ->
          {:ok, "Webhook verificado: hub.challenge ecoado corretamente"}

        {:ok, %{status: status, body: body}} ->
          {:error, "Falhou: HTTP #{status} — #{String.slice(body, 0, 200)}"}

        {:error, reason} ->
          {:error, "Falhou: #{reason}"}
      end

    {:noreply, assign(socket, verify_result: result)}
  end

  def handle_event("save_settings", %{"settings" => params}, socket) do
    case Accounts.update_settings(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Configurações salvas") |> load()}
      {:error, cs} -> {:noreply, put_flash(socket, :error, inspect(Control.changeset_errors(cs)))}
    end
  end

  def handle_event("add_waba", %{"waba" => params}, socket) do
    case Accounts.upsert_waba(Map.put(params, "subscribed", true)) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, cs} -> {:noreply, put_flash(socket, :error, inspect(Control.changeset_errors(cs)))}
    end
  end

  def handle_event("toggle_subscribed", %{"id" => id}, socket) do
    waba = Accounts.get_waba(id)
    {:ok, _} = Accounts.set_subscribed(id, !waba.subscribed)
    {:noreply, load(socket)}
  end

  def handle_event("delete_waba", %{"id" => id}, socket) do
    {:ok, _} = id |> Accounts.get_waba() |> Accounts.delete_waba()
    {:noreply, load(socket)}
  end

  def handle_event("add_phone", %{"phone" => params}, socket) do
    case Accounts.upsert_phone_number(params) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, cs} -> {:noreply, put_flash(socket, :error, inspect(Control.changeset_errors(cs)))}
    end
  end

  def handle_event("delete_phone", %{"id" => id}, socket) do
    {:ok, _} = id |> Accounts.get_phone_number() |> Accounts.delete_phone_number()
    {:noreply, load(socket)}
  end

  def handle_event("create_token", _params, socket) do
    {:ok, _} = Accounts.create_token(Enum.map(Accounts.list_wabas(), & &1.id))
    {:noreply, load(socket)}
  end

  def handle_event("delete_token", %{"id" => token}, socket) do
    token = Enum.find(Accounts.list_tokens(), &(&1.token == token))
    if token, do: {:ok, _} = Accounts.delete_token(token)
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info(_event, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:config}>
      <.page
        title="Configuração"
        subtitle="Segredos, números e integração com a sua aplicação. Tudo local."
      >
        <div class="grid gap-4 lg:grid-cols-2">
          <.panel title="App Meta (fake)">
            <dl class="mb-4 grid grid-cols-[auto_1fr] items-baseline gap-x-4 gap-y-2 text-sm">
              <dt class="text-base-content/60">App ID</dt>
              <dd class="flex items-center gap-2 font-mono">
                {@app.id} <.copy_button text={@app.id} />
              </dd>
              <dt class="text-base-content/60">App secret</dt>
              <dd class="flex flex-wrap items-center gap-2 font-mono">
                <span>{if @reveal_secret, do: @app.app_secret, else: String.duplicate("•", 16)}</span>
                <.btn variant="ghost" phx-click="toggle_secret">
                  {if @reveal_secret, do: "Ocultar", else: "Mostrar"}
                </.btn>
                <.copy_button text={@app.app_secret} />
                <.btn
                  variant="ghost"
                  phx-click="regenerate_secret"
                  data-confirm="Regenerar o app secret? Sua aplicação precisará do novo valor."
                >
                  Regenerar
                </.btn>
              </dd>
            </dl>

            <.form for={@app_form} id="app-form" phx-submit="save_app" class="space-y-3">
              <label class="block text-sm">
                <span class="mb-1 block text-base-content/70">Webhook URL (sua aplicação)</span>
                <input
                  name="app[webhook_url]"
                  value={@app_form[:webhook_url].value}
                  placeholder="http://localhost:8000/api/webhook/whatsapp"
                  class={input_class()}
                />
                <span
                  :for={err <- Map.get(@app_errors, :webhook_url, [])}
                  class="mt-1 block text-xs text-red-600"
                >{err}</span>
              </label>
              <label class="block text-sm">
                <span class="mb-1 block text-base-content/70">Verify token (WHATSAPP_WEBHOOK_VERIFY_TOKEN)</span>
                <input
                  name="app[verify_token]"
                  value={@app_form[:verify_token].value}
                  class={input_class()}
                />
              </label>
              <div class="flex flex-wrap items-center gap-2">
                <.btn type="submit" variant="primary">Salvar</.btn>
                <.btn phx-click="verify">Verificar webhook</.btn>
              </div>
            </.form>
            <p
              :if={@verify_result}
              class={[
                "mt-3 rounded-lg px-3 py-2 text-sm",
                elem(@verify_result, 0) == :ok &&
                  "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
                elem(@verify_result, 0) == :error && "bg-red-500/10 text-red-700 dark:text-red-300"
              ]}
            >
              {elem(@verify_result, 1)}
            </p>
          </.panel>

          <.panel title=".env da sua aplicação">
            <:actions><.copy_button text={@env_block} label="Copiar tudo" /></:actions>
            <pre
              id="env-block"
              class="overflow-x-auto rounded-lg bg-base-200 p-3 font-mono text-xs leading-relaxed"
            >{@env_block}</pre>
            <p class="mt-2 text-xs text-base-content/60">
              Os nomes das variáveis são sugestões: use os nomes que a sua aplicação já lê.
              O essencial é trocar a base URL da Graph API para o whelx.
            </p>
          </.panel>

          <.panel title="Comportamento">
            <.form
              for={@settings_form}
              id="settings-form"
              phx-submit="save_settings"
              class="grid grid-cols-2 gap-3 text-sm"
            >
              <label>
                <span class="mb-1 block text-base-content/70">Retry de webhook</span>
                <select name="settings[webhook_retry_profile]" class={input_class()}>
                  {Phoenix.HTML.Form.options_for_select(
                    [{"Rápido (dev)", "fast"}, {"Realista (Meta)", "realistic"}],
                    @settings_form[:webhook_retry_profile].value
                  )}
                </select>
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Aprovação de template</span>
                <select name="settings[template_approval_policy]" class={input_class()}>
                  {Phoenix.HTML.Form.options_for_select(
                    [
                      {"Manual", "manual"},
                      {"Aprovar automático", "auto_approve"},
                      {"Rejeitar automático", "auto_reject"}
                    ],
                    @settings_form[:template_approval_policy].value
                  )}
                </select>
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Revisão após (ms)</span>
                <input
                  type="number"
                  name="settings[template_review_after_ms]"
                  value={@settings_form[:template_review_after_ms].value}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Motivo de rejeição</span>
                <input
                  name="settings[template_reject_reason]"
                  value={@settings_form[:template_reject_reason].value}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">accepted → sent (ms)</span>
                <input
                  type="number"
                  name="settings[sent_delay_ms]"
                  value={@settings_form[:sent_delay_ms].value}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">sent → delivered (ms)</span>
                <input
                  type="number"
                  name="settings[delivered_delay_ms]"
                  value={@settings_form[:delivered_delay_ms].value}
                  class={input_class()}
                />
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Pair rate limit (131056)</span>
                <select name="settings[pair_rate_limit_enabled]" class={input_class()}>
                  {Phoenix.HTML.Form.options_for_select(
                    [{"Desligado", "false"}, {"Ligado", "true"}],
                    to_string(@settings_form[:pair_rate_limit_enabled].value)
                  )}
                </select>
              </label>
              <label>
                <span class="mb-1 block text-base-content/70">Burst / intervalo (ms)</span>
                <span class="flex gap-2">
                  <input
                    type="number"
                    name="settings[pair_rate_limit_burst]"
                    value={@settings_form[:pair_rate_limit_burst].value}
                    class={input_class()}
                  />
                  <input
                    type="number"
                    name="settings[pair_rate_limit_interval_ms]"
                    value={@settings_form[:pair_rate_limit_interval_ms].value}
                    class={input_class()}
                  />
                </span>
              </label>
              <div class="col-span-2">
                <.btn type="submit" variant="primary">Salvar</.btn>
              </div>
            </.form>
          </.panel>

          <.panel title="Tokens de acesso">
            <:actions>
              <.btn phx-click="create_token">Gerar token</.btn>
            </:actions>
            <ul class="space-y-2">
              <li
                :for={token <- @tokens}
                class="flex items-center gap-2 rounded-lg bg-base-200 px-3 py-2 text-xs"
              >
                <span class="min-w-0 flex-1 truncate font-mono">{token.token}</span>
                <span class="text-base-content/60">{length(token.waba_ids)} WABA(s)</span>
                <.copy_button text={token.token} label="" />
                <.btn
                  variant="danger"
                  phx-click="delete_token"
                  phx-value-id={token.token}
                  data-confirm="Apagar token?"
                >
                  <.icon name="hero-trash" class="size-4" />
                </.btn>
              </li>
            </ul>
          </.panel>
        </div>

        <.panel title="WABAs e números" class="mt-4">
          <:actions>
            <.form for={%{}} as={:waba} id="waba-form" phx-submit="add_waba" class="flex gap-2">
              <input name="waba[name]" placeholder="Nome do WABA" required class={input_class()} />
              <.btn type="submit">Adicionar</.btn>
            </.form>
          </:actions>
          <div class="space-y-3">
            <div :for={{waba, phones} <- @wabas} class="rounded-lg border border-base-300 p-3">
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-semibold">{waba.name}</span>
                <span class="font-mono text-xs text-base-content/60">{waba.id}</span>
                <span
                  :if={waba.override_callback_uri}
                  class="font-mono text-xs text-sky-600"
                  title="override_callback_uri do WABA"
                >
                  → {waba.override_callback_uri}
                </span>
                <.copy_button text={waba.id} label="" />
                <button phx-click="toggle_subscribed" phx-value-id={waba.id} class="ml-auto">
                  <.badge color={if waba.subscribed, do: "green", else: "yellow"}>
                    {if waba.subscribed, do: "subscribed_apps ✓", else: "sem subscribed_apps"}
                  </.badge>
                </button>
                <.btn
                  variant="danger"
                  phx-click="delete_waba"
                  phx-value-id={waba.id}
                  data-confirm="Apagar WABA e seus números?"
                >
                  <.icon name="hero-trash" class="size-4" />
                </.btn>
              </div>
              <table class="mt-2 w-full text-sm">
                <tr :for={phone <- phones} class="border-t border-base-300">
                  <td class="py-1.5 font-mono text-xs">
                    {phone.id} <.copy_button text={phone.id} label="" />
                  </td>
                  <td class="py-1.5">{phone.display_phone_number}</td>
                  <td class="py-1.5 text-base-content/70">
                    {phone.verified_name}
                    <span
                      :if={phone.override_callback_uri}
                      class="block font-mono text-[11px] text-sky-600"
                    >
                      → {phone.override_callback_uri}
                    </span>
                  </td>
                  <td class="py-1.5 text-xs text-base-content/60">{phone.throughput_mps} msg/s</td>
                  <td class="py-1.5 text-right">
                    <.btn
                      variant="danger"
                      phx-click="delete_phone"
                      phx-value-id={phone.id}
                      data-confirm="Apagar número?"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </.btn>
                  </td>
                </tr>
              </table>
              <.form
                for={%{}}
                as={:phone}
                id={"phone-form-#{waba.id}"}
                phx-submit="add_phone"
                class="mt-2 grid grid-cols-2 gap-2 md:grid-cols-4"
              >
                <input type="hidden" name="phone[waba_id]" value={waba.id} />
                <input
                  name="phone[display_phone_number]"
                  placeholder="+55 11 4000-0001"
                  required
                  class={input_class()}
                />
                <input
                  name="phone[verified_name]"
                  placeholder="Nome verificado"
                  required
                  class={input_class()}
                />
                <input
                  type="number"
                  name="phone[throughput_mps]"
                  placeholder="80 msg/s"
                  class={input_class()}
                />
                <.btn type="submit">Adicionar número</.btn>
              </.form>
            </div>
          </div>
        </.panel>
      </.page>
    </Layouts.app>
    """
  end
end
