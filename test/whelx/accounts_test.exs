defmodule Whelx.AccountsTest do
  use Whelx.DataCase
  alias Whelx.Accounts

  describe "bootstrap!/0" do
    test "creates a default app, waba, phone number and token exactly once" do
      :ok = Accounts.bootstrap!()
      :ok = Accounts.bootstrap!()

      assert %{id: app_id, app_secret: secret, verify_token: verify} = Accounts.get_app()
      assert app_id =~ ~r/^\d{15}$/
      assert String.length(secret) == 32
      assert String.length(verify) == 24
      assert [waba] = Accounts.list_wabas()
      assert [_phone] = Accounts.list_phone_numbers(waba.id)
      assert [token] = Accounts.list_tokens()
      assert String.starts_with?(token.token, "EAA")
      assert token.waba_ids == [waba.id]
    end
  end

  describe "tokens" do
    setup do
      :ok = Accounts.bootstrap!()
      [waba] = Accounts.list_wabas()
      %{waba: waba}
    end

    test "verify_token/1 accepts valid tokens and rejects unknown or expired ones", %{waba: waba} do
      {:ok, token} = Accounts.create_token([waba.id])
      assert {:ok, _} = Accounts.verify_token(token.token)
      assert :error = Accounts.verify_token("EAAnope")
      assert :error = Accounts.verify_token(nil)

      {:ok, expired} =
        Accounts.create_token([waba.id], expires_at: DateTime.add(DateTime.utc_now(), -60))

      assert :error = Accounts.verify_token(expired.token)
    end

    test "token_can_access?/2 is scoped to the token's wabas", %{waba: waba} do
      {:ok, other} = Accounts.upsert_waba(%{name: "Outra loja"})
      {:ok, token} = Accounts.create_token([waba.id])
      assert Accounts.token_can_access?(token, waba.id)
      refute Accounts.token_can_access?(token, other.id)
    end

    test "upsert_token/1 rejects tokens without the EAA prefix" do
      assert {:error, changeset} = Accounts.upsert_token(%{token: "abc", waba_ids: []})
      assert "must start with EAA" in errors_on(changeset).token
    end
  end

  describe "upserts" do
    setup do
      :ok = Accounts.bootstrap!()
    end

    test "upsert_waba/1 updates in place when the id exists" do
      [waba] = Accounts.list_wabas()
      {:ok, updated} = Accounts.upsert_waba(%{id: waba.id, name: "Pizzaria"})
      assert updated.id == waba.id
      assert [%{name: "Pizzaria"}] = Accounts.list_wabas()
    end

    test "upsert_app/1 validates webhook_url" do
      assert {:error, changeset} = Accounts.upsert_app(%{webhook_url: "ftp://nope"})
      assert "must be an http(s) URL" in errors_on(changeset).webhook_url

      assert {:ok, %{webhook_url: "http://myapp:8000/webhooks/whatsapp"}} =
               Accounts.upsert_app(%{webhook_url: "http://myapp:8000/webhooks/whatsapp"})
    end

    test "regenerate_app_secret/0 rotates the secret" do
      before = Accounts.get_app!().app_secret
      {:ok, app} = Accounts.regenerate_app_secret()
      assert app.app_secret != before
    end

    test "set_subscribed/2 toggles the webhook subscription" do
      [waba] = Accounts.list_wabas()
      assert {:ok, %{subscribed: true}} = Accounts.set_subscribed(waba.id, true)
      assert {:ok, %{subscribed: false}} = Accounts.set_subscribed(waba.id, false)
      assert {:error, :not_found} = Accounts.set_subscribed("000", true)
    end

    test "update_settings/1 validates allowed values" do
      assert {:ok, %{webhook_retry_profile: "realistic"}} =
               Accounts.update_settings(%{webhook_retry_profile: "realistic"})

      assert {:error, changeset} = Accounts.update_settings(%{template_approval_policy: "yolo"})
      assert "is invalid" in errors_on(changeset).template_approval_policy
    end
  end
end
