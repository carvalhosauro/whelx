defmodule Whelx.Fixtures do
  @moduledoc "Test data builders."
  alias Whelx.Accounts

  def account_fixture(opts \\ []) do
    {:ok, app} =
      Accounts.upsert_app(%{
        webhook_url: Keyword.get(opts, :webhook_url, "http://pigz.test/api/webhook/whatsapp")
      })

    {:ok, waba} =
      Accounts.upsert_waba(%{
        name: "Loja Teste",
        subscribed: Keyword.get(opts, :subscribed, true)
      })

    {:ok, phone} =
      Accounts.upsert_phone_number(%{
        waba_id: waba.id,
        display_phone_number: "+55 11 4000-0001",
        verified_name: "Loja Teste",
        throughput_mps: Keyword.get(opts, :throughput_mps, 80)
      })

    {:ok, token} = Accounts.create_token([waba.id])
    %{app: app, waba: waba, phone: phone, token: token.token}
  end
end
