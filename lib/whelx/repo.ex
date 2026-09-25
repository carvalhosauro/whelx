defmodule Whelx.Repo do
  use Ecto.Repo,
    otp_app: :whelx,
    adapter: Ecto.Adapters.SQLite3
end
