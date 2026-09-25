defmodule Whelx.Graph.ObjectResolver do
  @moduledoc "Resolves a Graph object id to the entity it names."
  alias Whelx.Accounts

  def resolve(id) do
    cond do
      waba = Accounts.get_waba(id) -> {:waba, waba}
      phone = Accounts.get_phone_number(id) -> {:phone_number, phone}
      match?(%{id: ^id}, Accounts.get_app()) -> {:app, Accounts.get_app()}
      true -> :not_found
    end
  end
end
