defmodule Whelx.PeerRequestsTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Chaos, Control, Templates, Webhooks}
  alias Whelx.Messaging.Throughput
  alias Whelx.Webhooks.Payload

  setup do
    Throughput.reset()
    Chaos.reset_counters()
    test_pid = self()

    Req.Test.stub(Whelx.Webhooks.Client, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(test_pid, {:hit, conn.method, conn.host, conn.request_path, conn.query_params})

      case conn.method do
        "GET" -> Plug.Conn.send_resp(conn, 200, conn.query_params["hub.challenge"] || "")
        _ -> Plug.Conn.send_resp(conn, 200, "OK")
      end
    end)

    account_fixture(webhook_url: "http://app.test/hook")
  end

  defp text(to),
    do: %{
      "messaging_product" => "whatsapp",
      "to" => to,
      "type" => "text",
      "text" => %{"body" => "x"}
    }

  defp send_graph(token, phone, body),
    do: build_conn() |> graph_auth(token) |> post("/v25.0/#{phone.id}/messages", body)

  describe "1. 130429 text" do
    test "error_data.details matches Meta", %{token: token, phone: phone} do
      {:ok, phone} = Accounts.upsert_phone_number(%{id: phone.id, throughput_mps: 1})

      conn =
        Enum.find_value(1..5, fn _ ->
          c = send_graph(token, phone, text("5511977776666"))
          if c.status == 400, do: c
        end)

      assert json_response(conn, 400)["error"]["error_data"]["details"] ==
               "Cloud API message throughput has been reached."
    end
  end

  describe "2. webhook override per WABA and per number" do
    test "POST subscribed_apps with override verifies the callback and routes deliveries", %{
      token: token,
      waba: waba
    } do
      conn =
        build_conn()
        |> graph_auth(token)
        |> post("/v25.0/#{waba.id}/subscribed_apps", %{
          "override_callback_uri" => "http://waba.test/hook",
          "verify_token" => "wtok"
        })

      assert json_response(conn, 200) == %{"success" => true}

      assert_received {:hit, "GET", "waba.test", "/hook",
                       %{"hub.mode" => "subscribe", "hub.verify_token" => "wtok"}}

      body =
        build_conn()
        |> graph_auth(token)
        |> get("/v25.0/#{waba.id}/subscribed_apps")
        |> json_response(200)

      assert [
               %{
                 "override_callback_uri" => "http://waba.test/hook",
                 "whatsapp_business_api_data" => %{"id" => _}
               }
             ] = body["data"]

      {:ok, d} = Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}))
      :ok = Webhooks.attempt(d, 1)
      assert_received {:hit, "POST", "waba.test", "/hook", _}

      conn = build_conn() |> graph_auth(token) |> post("/v25.0/#{waba.id}/subscribed_apps")
      assert json_response(conn, 200) == %{"success" => true}
      {:ok, d} = Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}))
      :ok = Webhooks.attempt(d, 1)
      assert_received {:hit, "POST", "app.test", "/hook", _}
    end

    test "failed verification returns 2200 and keeps the previous callback", %{
      token: token,
      waba: waba
    } do
      Req.Test.stub(Whelx.Webhooks.Client, fn conn -> Plug.Conn.send_resp(conn, 403, "nope") end)

      conn =
        build_conn()
        |> graph_auth(token)
        |> post("/v25.0/#{waba.id}/subscribed_apps", %{
          "override_callback_uri" => "http://bad.test/hook",
          "verify_token" => "x"
        })

      assert %{"error" => %{"code" => 2200}} = json_response(conn, 400)
      assert Accounts.get_waba(waba.id).override_callback_uri == nil
    end

    test "phone override has precedence and GET webhook_configuration shows all levels", %{
      token: token,
      waba: waba,
      phone: phone
    } do
      build_conn()
      |> graph_auth(token)
      |> post("/v25.0/#{waba.id}/subscribed_apps", %{
        "override_callback_uri" => "http://waba.test/hook",
        "verify_token" => "w"
      })

      conn =
        build_conn()
        |> graph_auth(token)
        |> post("/v25.0/#{phone.id}", %{
          "webhook_configuration" => %{
            "override_callback_uri" => "http://phone.test/hook",
            "verify_token" => "p"
          }
        })

      assert json_response(conn, 200) == %{"success" => true}

      body =
        build_conn()
        |> graph_auth(token)
        |> get("/v25.0/#{phone.id}?fields=webhook_configuration")
        |> json_response(200)

      assert body == %{
               "id" => phone.id,
               "webhook_configuration" => %{
                 "phone_number" => "http://phone.test/hook",
                 "whatsapp_business_account" => "http://waba.test/hook",
                 "application" => "http://app.test/hook"
               }
             }

      payload = Payload.envelope(waba.id, "messages", %{"metadata" => Payload.metadata(phone)})
      {:ok, d} = Webhooks.enqueue(waba.id, "messages", payload)
      flush()
      :ok = Webhooks.attempt(d, 1)
      assert_received {:hit, "POST", "phone.test", "/hook", _}

      build_conn()
      |> graph_auth(token)
      |> post("/v25.0/#{phone.id}", %{"webhook_configuration" => %{"override_callback_uri" => ""}})

      assert Accounts.get_phone_number(phone.id).override_callback_uri == nil
    end

    test "seed accepts overrides and the app webhook can stay empty", %{waba: waba} do
      {:ok, _} = Accounts.upsert_app(%{webhook_url: nil})

      {:ok, _} =
        Control.seed(%{
          "wabas" => [
            %{
              "id" => waba.id,
              "name" => "Loja",
              "override_callback_uri" => "http://waba.test/hook",
              "override_verify_token" => "w"
            }
          ]
        })

      {:ok, d} = Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}))
      assert d.state == "pending"
      :ok = Webhooks.attempt(d, 1)
      assert_received {:hit, "POST", "waba.test", "/hook", _}
    end
  end

  describe "3. pair rate limit 131056" do
    test "off by default", %{token: token, phone: phone} do
      for _ <- 1..3, do: assert(send_graph(token, phone, text("5511977776666")).status == 200)
    end

    test "burst then 1 per interval, per recipient", %{token: token, phone: phone} do
      {:ok, _} =
        Accounts.update_settings(%{
          pair_rate_limit_enabled: true,
          pair_rate_limit_burst: 2,
          pair_rate_limit_interval_ms: 6000
        })

      assert send_graph(token, phone, text("5511977776666")).status == 200
      assert send_graph(token, phone, text("5511977776666")).status == 200
      conn = send_graph(token, phone, text("5511977776666"))

      assert %{"error" => %{"code" => 131_056, "error_data" => %{"details" => details}}} =
               json_response(conn, 400)

      assert details =~ "same phone number"
      assert send_graph(token, phone, text("5511900000001")).status == 200
    end

    test "tokens refill over time" do
      alias Whelx.Messaging.PairLimit
      PairLimit.reset()
      assert :ok = PairLimit.check("p", "c", 1, 6000, 0)
      assert {:error, :pair_limited} = PairLimit.check("p", "c", 1, 6000, 1000)
      assert :ok = PairLimit.check("p", "c", 1, 6000, 6100)
    end
  end

  describe "4. chaos scoped to phone numbers" do
    test "sync errors only on scoped numbers", %{token: token, phone: phone, waba: waba} do
      {:ok, other} =
        Accounts.upsert_phone_number(%{
          waba_id: waba.id,
          display_phone_number: "+55 11 4000-0002",
          verified_name: "B"
        })

      {:ok, _} =
        Chaos.update_profile(%{
          sync_error_rate: 1.0,
          sync_error_codes: ["http_500"],
          phone_number_ids: [phone.id]
        })

      assert send_graph(token, phone, text("5511977776666")).status == 500
      assert send_graph(token, other, text("5511977776666")).status == 200
    end

    test "PUT /_whelx/chaos and seed accept phone_number_ids", %{phone: phone} do
      body =
        build_conn()
        |> put("/_whelx/chaos", %{"phone_number_ids" => [phone.id], "drop_rate" => 0.5})
        |> json_response(200)

      assert body["phone_number_ids"] == [phone.id]
      {:ok, snap} = Control.seed(%{"chaos" => %{"phone_number_ids" => []}})
      assert snap["chaos"]["phone_number_ids"] == []
    end

    test "webhook chaos only for scoped numbers", %{phone: phone, waba: waba} do
      {:ok, other} =
        Accounts.upsert_phone_number(%{
          waba_id: waba.id,
          display_phone_number: "+55 11 4000-0002",
          verified_name: "B"
        })

      {:ok, _} = Chaos.update_profile(%{drop_rate: 1.0, phone_number_ids: [phone.id]})
      scoped = Payload.envelope(waba.id, "messages", %{"metadata" => Payload.metadata(phone)})
      clean = Payload.envelope(waba.id, "messages", %{"metadata" => Payload.metadata(other)})
      assert {:ok, %{state: "dropped"}} = Webhooks.enqueue(waba.id, "messages", scoped)
      assert {:ok, %{state: "pending"}} = Webhooks.enqueue(waba.id, "messages", clean)
    end
  end

  describe "5. seed generates template examples" do
    test "missing example is filled from placeholders", %{waba: waba} do
      {:ok, _} =
        Control.seed(%{
          "templates" => [
            %{
              "waba_id" => waba.id,
              "name" => "promo_x",
              "language" => "pt_BR",
              "category" => "MARKETING",
              "components" => [
                %{"type" => "HEADER", "format" => "TEXT", "text" => "Oi {{1}}"},
                %{"type" => "BODY", "text" => "Promo {{1}} até {{2}}"}
              ]
            }
          ]
        })

      [t] = Templates.list_all(waba.id)
      body = Enum.find(t.components, &(&1["type"] == "BODY"))
      assert body["example"]["body_text"] == [["example 1", "example 2"]]
      header = Enum.find(t.components, &(&1["type"] == "HEADER"))
      assert header["example"]["header_text"] == ["example 1"]
    end

    test "Graph creation still requires examples", %{waba: waba} do
      assert {:error, %{code: 100}} =
               Templates.create_template(waba.id, %{
                 "name" => "p",
                 "language" => "pt_BR",
                 "category" => "MARKETING",
                 "components" => [%{"type" => "BODY", "text" => "Oi {{1}}"}]
               })
    end
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
