defmodule WhelxWeb.TemplatesLive do
  use WhelxWeb, :live_view
  import WhelxWeb.UI
  alias Whelx.{Accounts, Control, Events, Templates}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe("templates")
      Events.subscribe("config")
    end

    {:ok, socket |> assign(page_title: "Templates", previewing: nil) |> load()}
  end

  defp load(socket) do
    settings = Accounts.get_settings()
    wabas = Map.new(Accounts.list_wabas(), &{&1.id, &1.name})
    assign(socket, templates: Templates.list_all(), wabas: wabas, settings: settings)
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    {:ok, _} = id |> Templates.get_template() |> Templates.approve()
    {:noreply, load(socket)}
  end

  def handle_event("reject", %{"id" => id}, socket) do
    {:ok, _} =
      id
      |> Templates.get_template()
      |> Templates.reject(socket.assigns.settings.template_reject_reason)

    {:noreply, load(socket)}
  end

  def handle_event("preview", %{"id" => id}, socket),
    do: {:noreply, assign(socket, previewing: Templates.get_template(id))}

  def handle_event("close_preview", _params, socket),
    do: {:noreply, assign(socket, previewing: nil)}

  def handle_event("policy", %{"policy" => params}, socket) do
    case Accounts.update_settings(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Política salva") |> load()}
      {:error, cs} -> {:noreply, put_flash(socket, :error, inspect(Control.changeset_errors(cs)))}
    end
  end

  @impl true
  def handle_info(_event, socket), do: {:noreply, load(socket)}

  defp status_color("APPROVED"), do: "green"
  defp status_color("REJECTED"), do: "red"
  defp status_color("PENDING"), do: "yellow"
  defp status_color(_), do: "gray"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:templates}>
      <.page
        title="Templates"
        subtitle="Criados pela pigz-api via POST /{waba}/message_templates. Aprove ou rejeite aqui."
      >
        <.panel title="Política de aprovação" class="mb-4">
          <form id="policy-form" phx-submit="policy" class="flex flex-wrap items-end gap-2 text-sm">
            <label>
              <span class="mb-1 block text-base-content/70">Política</span>
              <select name="policy[template_approval_policy]" class={input_class()}>
                {Phoenix.HTML.Form.options_for_select(
                  [
                    {"Manual", "manual"},
                    {"Aprovar automático", "auto_approve"},
                    {"Rejeitar automático", "auto_reject"}
                  ],
                  @settings.template_approval_policy
                )}
              </select>
            </label>
            <label>
              <span class="mb-1 block text-base-content/70">Após (ms)</span>
              <input
                type="number"
                name="policy[template_review_after_ms]"
                value={@settings.template_review_after_ms}
                class={input_class()}
              />
            </label>
            <label>
              <span class="mb-1 block text-base-content/70">Motivo de rejeição</span>
              <input
                name="policy[template_reject_reason]"
                value={@settings.template_reject_reason}
                class={input_class()}
              />
            </label>
            <.btn type="submit" variant="primary">Salvar</.btn>
          </form>
        </.panel>

        <div class="grid gap-4 lg:grid-cols-[1fr_22rem]">
          <.panel>
            <table class="w-full text-sm">
              <thead class="text-left text-xs uppercase text-base-content/60">
                <tr>
                  <th class="py-2">Nome</th><th>WABA</th><th>Categoria</th><th>Status</th><th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={t <- @templates} class="border-t border-base-300">
                  <td class="py-2">
                    <span class="font-medium">{t.name}</span>
                    <span class="block text-xs text-base-content/60">{t.language} · {t.id}</span>
                  </td>
                  <td class="text-xs">{@wabas[t.waba_id] || t.waba_id}</td>
                  <td class="text-xs">{t.category}</td>
                  <td>
                    <.badge color={status_color(t.status)}>{t.status}</.badge>
                    <span :if={t.rejected_reason} class="block text-[10px] text-red-600">{t.rejected_reason}</span>
                  </td>
                  <td class="whitespace-nowrap text-right">
                    <.btn variant="ghost" phx-click="preview" phx-value-id={t.id}>Ver</.btn>
                    <.btn
                      :if={t.status != "APPROVED"}
                      variant="ghost"
                      phx-click="approve"
                      phx-value-id={t.id}
                    >
                      Aprovar
                    </.btn>
                    <.btn
                      :if={t.status != "REJECTED"}
                      variant="danger"
                      phx-click="reject"
                      phx-value-id={t.id}
                    >
                      Rejeitar
                    </.btn>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@templates == []} class="py-6 text-center text-sm text-base-content/60">
              Nenhum template. Crie pelo painel da pigz-api ou via POST /_whelx/seed.
            </p>
          </.panel>

          <.panel :if={@previewing} title={"Preview · " <> @previewing.name}>
            <:actions>
              <.btn variant="ghost" phx-click="close_preview">
                <.icon name="hero-x-mark" class="size-4" />
              </.btn>
            </:actions>
            <div class="rounded-xl bg-[#efeae2] p-3 dark:bg-base-300">
              <div class="rounded-xl rounded-tl-sm bg-base-100 p-3 text-sm shadow-sm">
                <%= for c <- @previewing.components do %>
                  <p :if={c["type"] == "HEADER" and c["format"] == "TEXT"} class="mb-1 font-semibold">
                    {c["text"]}
                  </p>
                  <p
                    :if={c["type"] == "HEADER" and c["format"] != "TEXT"}
                    class="mb-1 text-xs opacity-60"
                  >
                    [{c["format"]}]
                  </p>
                  <p :if={c["type"] == "BODY"} class="whitespace-pre-wrap">{c["text"]}</p>
                  <p :if={c["type"] == "FOOTER"} class="mt-1 text-xs opacity-60">{c["text"]}</p>
                  <div
                    :if={c["type"] == "BUTTONS"}
                    class="mt-2 grid gap-1 border-t border-black/10 pt-2"
                  >
                    <span :for={b <- c["buttons"]} class="text-center font-medium text-sky-600">{b[
                      "text"
                    ]}</span>
                  </div>
                <% end %>
              </div>
            </div>
            <.json_block data={@previewing.components} class="mt-3 max-h-80" />
          </.panel>
        </div>
      </.page>
    </Layouts.app>
    """
  end
end
