defmodule Whelx.Mcp do
  @moduledoc """
  Minimal MCP server (JSON-RPC over Streamable HTTP, JSON responses only).
  Supports initialize, ping, tools/list, tools/call and notifications.
  """

  alias Whelx.Mcp.Tools

  @protocol_version "2025-06-18"

  @spec handle(String.t(), map()) ::
          {:ok, map()} | {:error, integer(), String.t()} | :notification
  def handle("notifications/" <> _, _params), do: :notification

  def handle("initialize", params) do
    {:ok,
     %{
       "protocolVersion" => params["protocolVersion"] || @protocol_version,
       "capabilities" => %{"tools" => %{}},
       "serverInfo" => %{
         "name" => "whelx",
         "version" => to_string(Application.spec(:whelx, :vsn))
       },
       "instructions" =>
         "whelx emula a WhatsApp Cloud API. Use send_as_contact para simular clientes, wait_for para aguardar respostas do bot e list_webhook_deliveries para inspecionar o que foi entregue."
     }}
  end

  def handle("ping", _params), do: {:ok, %{}}
  def handle("tools/list", _params), do: {:ok, %{"tools" => Tools.list()}}

  def handle("tools/call", %{"name" => name} = params) do
    if Tools.known?(name) do
      case Tools.call(name, params["arguments"] || %{}) do
        {:ok, result} -> {:ok, content(result, false)}
        {:error, message} -> {:ok, content(message, true)}
      end
    else
      {:error, -32_602, "Unknown tool: #{name}"}
    end
  end

  def handle(method, _params), do: {:error, -32_601, "Method not found: #{method}"}

  defp content(result, error?) do
    text = if is_binary(result), do: result, else: Jason.encode!(result, pretty: true)
    %{"content" => [%{"type" => "text", "text" => text}], "isError" => error?}
  end
end
