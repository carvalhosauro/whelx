defmodule WhelxWeb.OpsLiveTest do
  use WhelxWeb.ConnCase
  import Phoenix.LiveViewTest
  import Whelx.Fixtures
  alias Whelx.{Chaos, Messaging, Webhooks}
  alias Whelx.Graph.Validation
  alias Whelx.Messaging.Throughput

  setup do
    Throughput.reset()
    Chaos.reset_counters()
    account_fixture()
  end

  defp send_template(phone, to) do
    {:ok, req} =
      Validation.validate_send(%{
        "messaging_product" => "whatsapp",
        "to" => to,
        "type" => "template",
        "template" => %{
          "name" => "crm_campaign_message",
          "language" => %{"code" => "pt_BR"},
          "components" => [
            %{
              "type" => "body",
              "parameters" => [
                %{"type" => "text", "text" => "A"},
                %{"type" => "text", "text" => "B"}
              ]
            }
          ]
        }
      })

    {:ok, msg} = Messaging.send_outbound(phone, req)
    msg
  end

  test "campaign_stats/1 groups template sends by name and status", %{phone: phone, waba: waba} do
    approved_template_fixture(waba.id)
    for i <- 1..3, do: send_template(phone, "551190000000#{i}")
    [stats] = Messaging.campaign_stats(DateTime.add(DateTime.utc_now(), -60))
    assert %{name: "crm_campaign_message", total: 3, accepted: 3, failed: 0} = stats
  end

  test "campaigns page shows per-template counts", %{conn: conn, phone: phone, waba: waba} do
    approved_template_fixture(waba.id)
    for i <- 1..2, do: send_template(phone, "551190000000#{i}")
    {:ok, _view, html} = live(conn, ~p"/campaigns")
    assert html =~ "crm_campaign_message"
    assert html =~ "130429"
  end

  test "logs page lists graph requests and deliveries and redelivers", %{
    conn: conn,
    token: token,
    waba: waba
  } do
    build_conn() |> graph_auth(token) |> get("/v25.0/#{waba.id}")
    {:ok, _} = Whelx.Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "oi"})
    [delivery] = Webhooks.list_deliveries()

    {:ok, view, html} = live(conn, ~p"/logs")
    assert html =~ "/v25.0/#{waba.id}"

    html = view |> element("button", "Webhooks") |> render_click()
    assert html =~ "messages"

    view
    |> element(~s(button[phx-click="redeliver"][phx-value-id="#{delivery.id}"]))
    |> render_click()

    assert length(Webhooks.list_deliveries()) == 2

    html =
      view
      |> element(~s(td.font-mono[phx-click="select_delivery"][phx-value-id="#{delivery.id}"]))
      |> render_click()

    assert html =~ "whatsapp_business_account"
  end

  test "chaos page applies presets and saves fields", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/chaos")
    view |> element(~s(button[phx-click="preset"][phx-value-name="flaky"])) |> render_click()
    assert Chaos.get_profile().preset == "flaky"

    view
    |> form("#chaos-form", chaos: %{drop_rate: "0.25", seed: "7", phone_number_ids: "111, 222"})
    |> render_submit()

    assert %{drop_rate: 0.25, seed: 7, phone_number_ids: ["111", "222"]} = Chaos.get_profile()
  end
end
