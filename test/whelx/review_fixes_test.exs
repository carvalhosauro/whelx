defmodule Whelx.ReviewFixesTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Control, Templates, Webhooks}
  alias Whelx.Graph.{Error, Validation}
  alias Whelx.Messaging.Throughput
  alias Whelx.Webhooks.Payload

  setup do
    Throughput.reset()
    account_fixture()
  end

  describe "#1 webhook config changes between enqueue and attempt" do
    test "clearing webhook_url marks pending deliveries skipped instead of crashing", %{
      waba: waba
    } do
      {:ok, d} = Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}))
      {:ok, _} = Accounts.upsert_app(%{webhook_url: ""})
      assert :ok = Webhooks.attempt(d, 1)

      assert %{state: "skipped", last_error: "webhook_url não configurada"} =
               Webhooks.get_delivery(d.id)
    end

    test "unsubscribing the WABA marks pending deliveries skipped", %{waba: waba} do
      {:ok, d} = Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}))
      {:ok, _} = Accounts.set_subscribed(waba.id, false)
      assert :ok = Webhooks.attempt(d, 1)
      assert %{state: "skipped"} = Webhooks.get_delivery(d.id)
    end

    test "a client exception is recorded, not raised", %{waba: waba} do
      Req.Test.stub(Whelx.Webhooks.Client, fn _conn -> raise ArgumentError, "boom" end)
      {:ok, d} = Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}))
      assert {:error, msg} = Webhooks.attempt(d, 1)
      assert msg =~ "boom"
      assert %{state: "retrying"} = Webhooks.get_delivery(d.id)
    end
  end

  describe "#2 cross-site requests to the control API" do
    test "foreign Origin is rejected", %{conn: conn} do
      conn = conn |> put_req_header("origin", "https://evil.example") |> post("/_whelx/reset")
      assert conn.status == 403
    end

    test "same-origin and no-Origin requests pass", %{conn: conn} do
      assert conn
             |> put_req_header("origin", "http://www.example.com")
             |> post("/_whelx/reset")
             |> json_response(200)

      assert build_conn() |> post("/_whelx/reset") |> json_response(200)
    end

    test "form-encoded POSTs are rejected (only JSON bodies)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/_whelx/mcp", "jsonrpc=2.0&method=ping")

      assert conn.status == 415
    end
  end

  describe "#3 malformed payloads are code 100, not 500" do
    defp base(extra),
      do:
        Map.merge(
          %{
            "messaging_product" => "whatsapp",
            "to" => "5511999990000",
            "type" => "text",
            "text" => %{"body" => "x"}
          },
          extra
        )

    test "validate_send never raises" do
      bad = [
        base(%{"to" => %{"a" => 1}}),
        base(%{"context" => "wamid.x"}),
        base(%{
          "type" => "interactive",
          "interactive" => %{"type" => "button", "body" => %{"text" => "x"}, "action" => "nope"}
        }),
        base(%{
          "type" => "interactive",
          "interactive" => %{
            "type" => "list",
            "body" => %{"text" => "x"},
            "action" => %{"button" => "b", "sections" => [%{"rows" => "r"}]}
          }
        }),
        base(%{
          "type" => "interactive",
          "interactive" => %{"type" => "cta_url", "body" => %{"text" => "x"}, "action" => "nope"}
        }),
        base(%{
          "type" => "interactive",
          "interactive" => %{
            "type" => "order_details",
            "body" => %{"text" => "x"},
            "action" => "nope"
          }
        }),
        base(%{"type" => "interactive", "interactive" => "nope"}),
        base(%{"type" => "template", "template" => %{"name" => "x", "language" => "pt_BR"}})
      ]

      for payload <- bad do
        assert {:error, %Error{code: 100}} = Validation.validate_send(payload), inspect(payload)
      end
    end

    test "?fields as a list does not crash", %{conn: conn, waba: waba, token: token} do
      conn = conn |> graph_auth(token) |> get("/v25.0/#{waba.id}?fields[]=id")
      assert conn.status == 200
    end
  end

  test "#4 reset keeping templates keeps pending reviews", %{waba: waba} do
    {:ok, _} =
      Accounts.update_settings(%{
        template_approval_policy: "auto_approve",
        template_review_after_ms: 5_000
      })

    {:ok, t} = Templates.create_template(waba.id, template_params())
    :ok = Control.reset(["templates"])
    assert_enqueued(worker: Templates.ReviewWorker, args: %{"template_id" => t.id})
  end

  test "#5 unknown objects use GraphMethodException like Meta", %{conn: conn, token: token} do
    body = conn |> graph_auth(token) |> get("/v25.0/999999999999999") |> json_response(400)
    assert body["error"]["type"] == "GraphMethodException"
  end

  test "#7 REST reset accepts keep as a JSON list", %{conn: conn} do
    assert conn |> post("/_whelx/reset", %{"keep" => ["contacts"]}) |> json_response(200)
  end

  test "#8 invalid wa_id is an error, not a random contact", %{conn: conn} do
    assert %{"error" => _} =
             conn
             |> post("/_whelx/contacts/abc/messages", %{"type" => "text", "text" => "oi"})
             |> json_response(422)

    assert Whelx.Contacts.list_contacts() == []
  end

  test "#15 MCP limit as string" do
    conn =
      build_conn()
      |> post("/_whelx/mcp", %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "list_webhook_deliveries", "arguments" => %{"limit" => "10"}}
      })

    assert %{"result" => %{"isError" => false}} = json_response(conn, 200)
  end
end
