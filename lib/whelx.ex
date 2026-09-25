defmodule Whelx do
  @moduledoc """
  whelx: a local emulator of the WhatsApp Cloud API (Meta Graph API).
  """

  @doc "Base URL other services use to reach this whelx instance (media URLs, paging links)."
  @spec public_url() :: String.t()
  def public_url, do: Application.fetch_env!(:whelx, :public_url)

  @doc "Directory holding media binaries and uploads."
  @spec data_dir() :: String.t()
  def data_dir, do: Application.fetch_env!(:whelx, :data_dir)
end
