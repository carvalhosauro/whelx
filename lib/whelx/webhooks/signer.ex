defmodule Whelx.Webhooks.Signer do
  @moduledoc "X-Hub-Signature-256 as Meta computes it: hex HMAC-SHA256 of the raw body."

  @spec sign(iodata(), String.t()) :: String.t()
  def sign(body, secret),
    do: "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)
end
