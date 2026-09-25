defmodule Whelx.Webhooks.Client do
  @moduledoc "HTTP client used to call the configured webhook URL."

  @timeout 10_000

  @spec timeout_ms() :: pos_integer()
  def timeout_ms, do: @timeout

  def post(url, body, headers) do
    Req.post(url, [body: body, headers: headers] ++ base_opts())
  end

  def get(url, params) do
    Req.get(url, [params: params] ++ base_opts())
  end

  defp base_opts do
    [receive_timeout: @timeout, retry: false, decode_body: false, redirect: false] ++
      Application.get_env(:whelx, :webhook_req_options, [])
  end
end
