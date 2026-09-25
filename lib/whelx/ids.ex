defmodule Whelx.Ids do
  @moduledoc "Generates identifiers shaped like the ones Meta returns."

  @alnum ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

  @spec numeric_id() :: String.t()
  def numeric_id, do: Integer.to_string(Enum.random(1..9)) <> digits(14)

  @spec wamid() :: String.t()
  def wamid, do: "wamid.HBgN" <> Base.encode64(:crypto.strong_rand_bytes(30))

  @spec access_token() :: String.t()
  def access_token, do: "EAA" <> alnum(80)

  @spec app_secret() :: String.t()
  def app_secret, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  @spec verify_token() :: String.t()
  def verify_token, do: alnum(24)

  @spec upload_session_id() :: String.t()
  def upload_session_id,
    do: "upload:" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  @spec media_handle() :: String.t()
  def media_handle, do: "4:" <> Base.encode64(:crypto.strong_rand_bytes(24))

  @spec fbtrace_id() :: String.t()
  def fbtrace_id, do: alnum(11)

  @doc "Brazilian mobile number (São Paulo area) in WhatsApp wa_id format."
  @spec contact_wa_id() :: String.t()
  def contact_wa_id, do: "55119" <> digits(8)

  @spec alnum(pos_integer()) :: String.t()
  def alnum(n), do: for(_ <- 1..n, into: "", do: <<Enum.random(@alnum)>>)

  @spec digits(pos_integer()) :: String.t()
  def digits(n), do: for(_ <- 1..n, into: "", do: Integer.to_string(Enum.random(0..9)))
end
