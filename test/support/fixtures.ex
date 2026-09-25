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

  def template_params(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "crm_campaign_message",
        "language" => "pt_BR",
        "category" => "MARKETING",
        "components" => [
          %{
            "type" => "BODY",
            "text" => "Mensagem de *{{1}}*:\n\n{{2}}\n\n_Enviado via Pigz_",
            "example" => %{"body_text" => [["Pizzaria", "Promo de hoje"]]}
          }
        ]
      },
      overrides
    )
  end

  def approved_template_fixture(waba_id, overrides \\ %{}) do
    {:ok, template} =
      Whelx.Templates.seed_template(
        waba_id,
        Map.put(template_params(overrides), "status", "APPROVED")
      )

    template
  end
end
