defmodule WhelxWeb.Plugs.GraphRequestLogger do
  @moduledoc "Logs every Graph request/response to `graph_requests` (tokens masked)."
  @behaviour Plug
  import Plug.Conn
  alias Whelx.Logs

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    started = System.monotonic_time(:millisecond)

    register_before_send(conn, fn conn ->
      Logs.log_request(%{
        method: conn.method,
        path: conn.request_path,
        query: mask_query(conn.query_string),
        request_headers: headers(conn),
        request_body: request_body(conn),
        response_status: conn.status,
        response_body: response_body(conn),
        duration_ms: System.monotonic_time(:millisecond) - started,
        chaos_tag: conn.assigns[:chaos_tag],
        internal_error: conn.status == 500 and is_nil(conn.assigns[:chaos_tag])
      })

      conn
    end)
  end

  defp headers(conn) do
    conn.req_headers
    |> Enum.filter(fn {k, _} -> k in ~w(authorization content-type file_offset user-agent) end)
    |> Map.new(fn
      {"authorization", value} -> {"authorization", mask_authorization(value)}
      pair -> pair
    end)
  end

  defp mask_authorization(value) do
    case String.split(value, " ", parts: 2) do
      [scheme, token] -> scheme <> " " <> Logs.mask(token)
      _ -> Logs.mask(value)
    end
  end

  defp mask_query(""), do: nil

  defp mask_query(query) do
    query
    |> URI.decode_query()
    |> Map.new(fn
      {"access_token", token} -> {"access_token", Logs.mask(token)}
      pair -> pair
    end)
    |> URI.encode_query()
  end

  defp request_body(conn) do
    body = conn.assigns[:raw_body]
    type = conn |> get_req_header("content-type") |> List.first() |> to_string()

    cond do
      is_nil(body) or body == "" -> nil
      type =~ "json" or type =~ "urlencoded" -> Logs.truncate(body)
      true -> "<binary #{byte_size(body)} bytes>"
    end
  end

  defp response_body(conn) do
    body = IO.iodata_to_binary(conn.resp_body || "")
    type = conn |> get_resp_header("content-type") |> List.first() |> to_string()

    if type =~ "json" or body == "",
      do: Logs.truncate(body),
      else: "<binary #{byte_size(body)} bytes>"
  end
end
