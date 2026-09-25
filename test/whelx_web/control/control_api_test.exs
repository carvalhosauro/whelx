defmodule WhelxWeb.Control.ControlApiTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Messaging}
  alias Whelx.Graph.Validation
  alias Whelx.Messaging.Throughput

  setup do
    Throughput.reset()

    Req.Test.stub(Whelx.Webhooks.Client, fn conn ->
      Plug.Conn.send_resp(
        conn,
        200,
        Plug.Conn.fetch_query_params(conn).query_params["hub.challenge"] || "OK"
      )
    end)

    account_fixture()
  end

  test "POST /_whelx/seed and GET /_whelx/config", %{conn: conn} do
    body = %{
      "wabas" => [
        %{
          "id" => "999000999000999",
          "name" => "Seeded",
          "subscribed" => true,
          "phone_numbers" => [
            %{
              "id" => "888000888000888",
              "display_phone_number" => "+55 11 4000-0002",
              "verified_name" => "Seeded"
            }
          ]
        }
      ],
      "tokens" => [%{"token" => "EAAseeded", "wabas" => "all"}]
    }

    assert %{"wabas" => wabas} = conn |> post("/_whelx/seed", body) |> json_response(200)
    assert Enum.any?(wabas, &(&1["id"] == "999000999000999"))

    assert %{"app" => %{"app_id" => _}, "settings" => _, "chaos" => _} =
             build_conn() |> get("/_whelx/config") |> json_response(200)
  end

  test "seed errors return 422", %{conn: conn} do
    assert %{"error" => _} =
             conn
             |> post("/_whelx/seed", %{"tokens" => [%{"token" => "bad"}]})
             |> json_response(422)
  end

  test "PUT /_whelx/config updates app and settings", %{conn: conn} do
    body = %{
      "app" => %{"webhook_url" => "http://myapp:8000/webhooks/whatsapp"},
      "settings" => %{"sent_delay_ms" => 10}
    }

    assert %{
             "app" => %{"webhook_url" => "http://myapp:8000/webhooks/whatsapp"},
             "settings" => %{"sent_delay_ms" => 10}
           } = conn |> put("/_whelx/config", body) |> json_response(200)
  end

  test "POST /_whelx/tokens creates a token for all wabas", %{conn: conn, waba: waba} do
    assert %{"token" => "EAA" <> _, "waba_ids" => [id]} =
             conn |> post("/_whelx/tokens", %{}) |> json_response(201)

    assert id == waba.id
  end

  test "chaos: preset and fields", %{conn: conn} do
    assert %{"preset" => "flaky"} =
             conn |> put("/_whelx/chaos", %{"preset" => "flaky"}) |> json_response(200)

    assert %{"drop_rate" => 0.5} =
             build_conn() |> put("/_whelx/chaos", %{"drop_rate" => 0.5}) |> json_response(200)

    assert %{"error" => _} =
             build_conn() |> put("/_whelx/chaos", %{"preset" => "doom"}) |> json_response(422)

    assert %{"seed" => _} = build_conn() |> get("/_whelx/chaos") |> json_response(200)
  end

  test "contacts CRUD, bulk and presence", %{conn: conn} do
    assert %{"wa_id" => "5511977776666"} =
             conn
             |> post("/_whelx/contacts", %{"wa_id" => "5511977776666", "profile_name" => "Ana"})
             |> json_response(201)

    assert %{"count" => 5} =
             build_conn() |> post("/_whelx/contacts/bulk", %{"count" => 5}) |> json_response(201)

    assert length(build_conn() |> get("/_whelx/contacts") |> json_response(200)) == 6

    assert %{"online" => false, "behavior" => "blocked"} =
             build_conn()
             |> patch("/_whelx/contacts/5511977776666", %{
               "online" => false,
               "behavior" => "blocked"
             })
             |> json_response(200)

    assert %{"wa_id" => "5511977776666"} =
             build_conn() |> get("/_whelx/contacts/5511977776666") |> json_response(200)

    assert response(build_conn() |> delete("/_whelx/contacts/5511977776666"), 204)

    assert %{"error" => "not_found"} =
             build_conn() |> get("/_whelx/contacts/5511977776666") |> json_response(404)

    assert %{"error" => "validation"} =
             build_conn() |> post("/_whelx/contacts", %{"wa_id" => "1"}) |> json_response(422)
  end

  test "send as contact, list messages and click interactive", %{conn: conn, phone: phone} do
    assert %{"wamid" => _, "direction" => "inbound", "contact" => "5511977776666"} =
             conn
             |> post("/_whelx/contacts/5511977776666/messages", %{
               "type" => "text",
               "text" => "oi"
             })
             |> json_response(201)

    {:ok, req} =
      Validation.validate_send(%{
        "messaging_product" => "whatsapp",
        "to" => "5511977776666",
        "type" => "interactive",
        "interactive" => %{
          "type" => "button",
          "body" => %{"text" => "?"},
          "action" => %{
            "buttons" => [%{"type" => "reply", "reply" => %{"id" => "y", "title" => "Sim"}}]
          }
        }
      })

    {:ok, out} = Messaging.send_outbound(phone, req)

    assert %{"type" => "interactive", "context_wamid" => ctx} =
             build_conn()
             |> post("/_whelx/contacts/5511977776666/reply-interactive", %{
               "wamid" => out.wamid,
               "id" => "y"
             })
             |> json_response(201)

    assert ctx == out.wamid

    assert [%{"direction" => "outbound"}] =
             build_conn()
             |> get("/_whelx/messages?direction=outbound&contact=5511977776666")
             |> json_response(200)

    assert %{"error" => _} =
             build_conn()
             |> post("/_whelx/contacts/5511977776666/messages", %{"type" => "sticker"})
             |> json_response(422)
  end

  test "conversations: show, open and expire-window", %{conn: conn} do
    %{"conversation_id" => id} =
      conn
      |> post("/_whelx/contacts/5511977776666/messages", %{"type" => "text", "text" => "oi"})
      |> json_response(201)

    assert %{"window_open" => true, "messages" => [_]} =
             build_conn() |> get("/_whelx/conversations/#{id}") |> json_response(200)

    assert %{"window_open" => false} =
             build_conn()
             |> post("/_whelx/conversations/#{id}/expire-window")
             |> json_response(200)

    assert %{"unread_count" => 0} =
             build_conn() |> post("/_whelx/conversations/#{id}/open") |> json_response(200)

    assert %{"error" => "not_found"} =
             build_conn() |> get("/_whelx/conversations/0") |> json_response(404)
  end

  test "templates: list, approve and reject", %{conn: conn, waba: waba} do
    {:ok, t} = Whelx.Templates.create_template(waba.id, template_params())
    assert [%{"status" => "PENDING"}] = conn |> get("/_whelx/templates") |> json_response(200)

    assert %{"status" => "APPROVED"} =
             build_conn() |> post("/_whelx/templates/#{t.id}/approve") |> json_response(200)

    assert %{"status" => "REJECTED", "rejected_reason" => "SPAM"} =
             build_conn()
             |> post("/_whelx/templates/#{t.id}/reject", %{"reason" => "SPAM"})
             |> json_response(200)
  end

  test "webhooks: deliveries, redeliver and verify; requests log", %{
    conn: conn,
    token: token,
    waba: waba
  } do
    conn |> post("/_whelx/contacts/5511977776666/messages", %{"type" => "text", "text" => "oi"})

    assert [%{"id" => id, "kind" => "messages"}] =
             build_conn() |> get("/_whelx/webhooks/deliveries") |> json_response(200)

    assert %{"state" => "pending"} =
             build_conn()
             |> post("/_whelx/webhooks/deliveries/#{id}/redeliver")
             |> json_response(201)

    assert %{"ok" => true, "status" => 200} =
             build_conn() |> post("/_whelx/webhooks/verify") |> json_response(200)

    build_conn() |> graph_auth(token) |> get("/v25.0/#{waba.id}")
    assert [%{"path" => path}] = build_conn() |> get("/_whelx/requests") |> json_response(200)
    assert path == "/v25.0/#{waba.id}"
  end

  test "reset keeps config", %{conn: conn} do
    conn |> post("/_whelx/contacts/5511977776666/messages", %{"type" => "text", "text" => "oi"})

    assert %{"ok" => true} =
             build_conn() |> post("/_whelx/reset?keep=contacts") |> json_response(200)

    assert build_conn() |> get("/_whelx/messages") |> json_response(200) == []
    assert [_] = Accounts.list_wabas()
  end
end
