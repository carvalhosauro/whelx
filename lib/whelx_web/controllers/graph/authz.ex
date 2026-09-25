defmodule WhelxWeb.Graph.Authz do
  @moduledoc "Token scope checks for Graph objects."
  alias Whelx.Accounts
  alias Whelx.Graph.Error

  def waba(access_token, waba_id) do
    if Accounts.token_can_access?(access_token, waba_id), do: :ok, else: {:error, Error.new(200)}
  end
end
