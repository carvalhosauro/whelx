defmodule WhelxWeb.ConfigLiveTest do
  use WhelxWeb.ConnCase
  import Phoenix.LiveViewTest
  import Whelx.Fixtures
  alias Whelx.Accounts

  setup do
    account_fixture()
  end

  test "shows the env block and secrets", %{conn: conn, app: app} do
    {:ok, view, html} = live(conn, ~p"/config")
    assert html =~ "META_APP_ID=#{app.id}"
    assert html =~ "WEBHOOK_VERIFY_TOKEN=#{app.verify_token}"
    refute html =~ ~s(value="#{app.app_secret}")
    html = view |> element("button", "Mostrar") |> render_click()
    assert html =~ app.app_secret
  end

  test "saves webhook URL and settings", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/config")

    view
    |> form("#app-form",
      app: %{webhook_url: "http://myapp:8000/webhooks/whatsapp", verify_token: "tok"}
    )
    |> render_submit()

    assert %{webhook_url: "http://myapp:8000/webhooks/whatsapp", verify_token: "tok"} =
             Accounts.get_app()

    view
    |> form("#settings-form",
      settings: %{
        sent_delay_ms: 50,
        webhook_retry_profile: "realistic",
        pair_rate_limit_enabled: "true",
        pair_rate_limit_burst: 3
      }
    )
    |> render_submit()

    assert %{
             sent_delay_ms: 50,
             webhook_retry_profile: "realistic",
             pair_rate_limit_enabled: true,
             pair_rate_limit_burst: 3
           } =
             Accounts.get_settings()
  end

  test "invalid webhook URL shows an error", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/config")
    html = view |> form("#app-form", app: %{webhook_url: "ftp://x"}) |> render_submit()
    assert html =~ "must be an http(s) URL"
  end

  test "adds a WABA, a phone number and a token", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/config")
    view |> form("#waba-form", waba: %{name: "Hamburgueria"}) |> render_submit()
    waba = Enum.find(Accounts.list_wabas(), &(&1.name == "Hamburgueria"))
    assert waba

    view
    |> form("#phone-form-#{waba.id}",
      phone: %{display_phone_number: "+55 11 4000-9999", verified_name: "Burger"}
    )
    |> render_submit()

    assert [_] = Accounts.list_phone_numbers(waba.id)

    before = length(Accounts.list_tokens())
    view |> element("button", "Gerar token") |> render_click()
    assert length(Accounts.list_tokens()) == before + 1
  end

  test "regenerates the app secret", %{conn: conn, app: app} do
    {:ok, view, _} = live(conn, ~p"/config")
    view |> element("button", "Regenerar") |> render_click()
    assert Accounts.get_app!().app_secret != app.app_secret
  end

  test "navigation sidebar is present", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/config")

    for label <- ["Chat", "Contatos", "Templates", "Campanhas", "Logs", "Caos", "Config"],
        do: assert(html =~ label)
  end
end
