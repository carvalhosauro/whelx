defmodule Whelx.WebhooksTest do
  use Whelx.DataCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Webhooks}
  alias Whelx.Webhooks.{Delivery, DeliveryWorker, Payload, Signer}

  setup do
    ctx = account_fixture()
    test_pid = self()

    Req.Test.stub(Whelx.Webhooks.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook, conn.method, conn.req_headers, body, conn.query_string})
      Plug.Conn.send_resp(conn, 200, "OK")
    end)

    ctx
  end

  defp sample_payload(waba),
    do: Payload.envelope(waba.id, "messages", %{"messaging_product" => "whatsapp"})

  test "delivers signed payloads", %{waba: waba, app: app} do
    {:ok, delivery} = Webhooks.enqueue(waba.id, "messages", sample_payload(waba))
    assert %{success: 1} = Oban.drain_queue(queue: :webhooks)

    assert_received {:webhook, "POST", headers, body, _}

    expected =
      "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, app.app_secret, body), case: :lower)

    assert {"x-hub-signature-256", ^expected} = List.keyfind(headers, "x-hub-signature-256", 0)
    assert {"user-agent", "facebookexternalua"} = List.keyfind(headers, "user-agent", 0)
    assert {"content-type", "application/json"} = List.keyfind(headers, "content-type", 0)
    assert Jason.decode!(body) == sample_payload(waba)

    assert %Delivery{state: "delivered", attempts: 1, last_status: 200, signature: ^expected} =
             Webhooks.get_delivery(delivery.id)
  end

  test "Signer.sign/2 is hex HMAC-SHA256 with sha256= prefix" do
    assert Signer.sign("{}", "secret") ==
             "sha256=" <>
               Base.encode16(:crypto.mac(:hmac, :sha256, "secret", "{}"), case: :lower)
  end

  test "non-200 responses keep retrying until the last attempt", %{waba: waba} do
    Req.Test.stub(Whelx.Webhooks.Client, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    {:ok, d} = Webhooks.enqueue(waba.id, "messages", sample_payload(waba))

    assert {:error, "HTTP 500"} = Webhooks.attempt(d, 1)

    assert %{state: "retrying", last_status: 500, last_response_body: "boom"} =
             Webhooks.get_delivery(d.id)

    assert {:error, _} = Webhooks.attempt(Webhooks.get_delivery(d.id), 9)
    assert %{state: "failed", attempts: 9} = Webhooks.get_delivery(d.id)
  end

  test "connection refused is recorded, not raised", %{waba: waba} do
    Req.Test.stub(Whelx.Webhooks.Client, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    {:ok, d} = Webhooks.enqueue(waba.id, "messages", sample_payload(waba))
    assert {:error, message} = Webhooks.attempt(d, 1)
    assert message =~ "refused"

    assert %{state: "retrying", last_status: nil, last_error: ^message} =
             Webhooks.get_delivery(d.id)
  end

  test "skips when webhook_url is blank", %{waba: waba} do
    {:ok, _} = Accounts.upsert_app(%{webhook_url: nil})
    {:ok, d} = Webhooks.enqueue(waba.id, "messages", sample_payload(waba))
    assert d.state == "skipped"
    assert d.last_error =~ "webhook_url"
    refute_enqueued(worker: DeliveryWorker)
  end

  test "skips when the waba is not subscribed", %{waba: waba} do
    {:ok, _} = Accounts.set_subscribed(waba.id, false)
    {:ok, d} = Webhooks.enqueue(waba.id, "messages", sample_payload(waba))
    assert d.state == "skipped"
    assert d.last_error =~ "subscribed_apps"
  end

  test "backoff_seconds/2 follows the retry profile" do
    assert Enum.map(1..8, &Webhooks.backoff_seconds("fast", &1)) == [1, 2, 4, 8, 16, 32, 64, 128]
    assert Webhooks.backoff_seconds("realistic", 1) == 15
    assert Webhooks.backoff_seconds("realistic", 8) == 28_800
  end

  test "verify/0 performs the hub.challenge handshake", %{app: app} do
    Req.Test.stub(Whelx.Webhooks.Client, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["hub.mode"] == "subscribe"
      assert conn.query_params["hub.verify_token"] == app.verify_token
      Plug.Conn.send_resp(conn, 200, conn.query_params["hub.challenge"])
    end)

    assert {:ok, %{ok: true, status: 200}} = Webhooks.verify()

    Req.Test.stub(Whelx.Webhooks.Client, fn conn -> Plug.Conn.send_resp(conn, 200, "nope") end)
    assert {:ok, %{ok: false, status: 200}} = Webhooks.verify()

    {:ok, _} = Accounts.upsert_app(%{webhook_url: nil})
    assert {:error, "webhook_url não configurada"} = Webhooks.verify()
  end

  test "redeliver/1 creates a new delivery with the same payload", %{waba: waba} do
    {:ok, d} =
      Webhooks.enqueue(waba.id, "messages", sample_payload(waba), message_wamid: "wamid.X")

    {:ok, copy} = Webhooks.redeliver(d.id)
    assert copy.id != d.id
    assert copy.payload == d.payload
    assert copy.message_wamid == "wamid.X"
    assert length(Webhooks.list_deliveries(message_wamid: "wamid.X")) == 2
  end

  test "worker cancels when the delivery no longer exists" do
    assert {:cancel, :not_found} = perform_job(DeliveryWorker, %{"delivery_id" => -1})
  end
end
