defmodule WhelxWeb.Plugs.GraphChaos do
  @moduledoc "Injects latency and synchronous errors according to the chaos profile."
  @behaviour Plug
  import Plug.Conn
  alias Whelx.Chaos
  alias Whelx.Graph.Error

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    profile = Chaos.get_profile()
    if Chaos.active?(profile) and in_scope?(profile, conn), do: inject(conn, profile), else: conn
  end

  defp inject(conn, profile) do
    case Chaos.latency_ms(profile) do
      0 -> :ok
      ms -> Process.sleep(ms)
    end

    if Chaos.hit?(profile, :sync_error, profile.sync_error_rate) do
      code = Chaos.pick(profile, :sync_error_code, profile.sync_error_codes)

      conn
      |> assign(:chaos_tag, "sync_error:#{code}")
      |> WhelxWeb.Graph.Render.error(error_for(code, messages_route?(conn)))
      |> halt()
    else
      conn
    end
  end

  # Scoped chaos: the path object must be a scoped number, or a WABA that owns one.
  defp in_scope?(%{phone_number_ids: blank}, _conn) when blank in [nil, []], do: true

  defp in_scope?(profile, %Plug.Conn{path_params: %{"id" => id}}) do
    Chaos.applies?(profile, id) or
      Enum.any?(Whelx.Accounts.list_phone_numbers(id), &Chaos.applies?(profile, &1.id))
  end

  defp in_scope?(_profile, _conn), do: false

  defp messages_route?(conn),
    do: conn.method == "POST" and List.last(conn.path_info) == "messages"

  defp error_for("130429", true), do: Error.new(130_429)
  defp error_for("http_500", _), do: Error.new(1)
  defp error_for("http_503", _), do: Error.new(2)
  defp error_for(_code, _messages?), do: Error.new(131_000)
end
