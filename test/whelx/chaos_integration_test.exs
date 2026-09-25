defmodule Whelx.ChaosIntegrationTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Chaos, Logs, Messaging, Repo, Webhooks}
  alias Whelx.Graph.Validation
  alias Whelx.Messaging.{Message, Throughput}
  alias Whelx.Webhooks.{Delivery, Payload}

  setup do
    Throughput.reset()
    Chaos.reset_counters()
    {:ok, _} = Accounts.update_settings(%{sent_delay_ms: 0, delivered_delay_ms: 0})

    Req.Test.stub(Whelx.Webhooks.Client, fn conn -> Plug.Conn.send_resp(conn, 200, "OK") end)
    account_fixture()
  end

  defp text(to \\ "5511977776666"),
    do: %{
      "messaging_product" => "whatsapp",
      "to" => to,
      "type" => "text",
      "text" => %{"body" => "oi"}
    }

  test "sync errors: 130429 on messages, logged with chaos_tag", %{
    conn: conn,
    token: token,
    phone: phone
  } do
    {:ok, _} = Chaos.update_profile(%{sync_error_rate: 1.0, sync_error_codes: ["130429"]})
    conn = conn |> graph_auth(token) |> post("/v25.0/#{phone.id}/messages", text())
    assert %{"error" => %{"code" => 130_429}} = json_response(conn, 400)
    assert [%{chaos_tag: "sync_error:130429", internal_error: false}] = Logs.list_requests()
  end

  test "sync errors: 130429 elsewhere degrades to 131000; http_503 is code 2", %{
    conn: conn,
    token: token,
    waba: waba
  } do
    {:ok, _} = Chaos.update_profile(%{sync_error_rate: 1.0, sync_error_codes: ["130429"]})

    assert %{"error" => %{"code" => 131_000}} =
             conn |> graph_auth(token) |> get("/v25.0/#{waba.id}") |> json_response(500)

    {:ok, _} = Chaos.update_profile(%{sync_error_rate: 1.0, sync_error_codes: ["http_503"]})

    assert %{"error" => %{"code" => 2}} =
             build_conn() |> graph_auth(token) |> get("/v25.0/#{waba.id}") |> json_response(503)
  end

  test "latency is injected", %{conn: conn, token: token, waba: waba} do
    {:ok, _} = Chaos.update_profile(%{latency_min_ms: 60, latency_max_ms: 60})
    {micros, conn} = :timer.tc(fn -> conn |> graph_auth(token) |> get("/v25.0/#{waba.id}") end)
    assert conn.status == 200
    assert micros >= 60_000
  end

  test "async failure plans a failed status with a chaos code", %{phone: phone} do
    {:ok, _} =
      Messaging.receive_inbound(phone.id, "5511977776666", %{
        type: "text",
        content: %{"body" => "oi"},
        context_wamid: nil
      })

    {:ok, _} = Chaos.update_profile(%{async_fail_rate: 1.0, async_fail_codes: [131_049]})
    {:ok, req} = Validation.validate_send(text())
    {:ok, msg} = Messaging.send_outbound(phone, req)

    assert %Message{planned_failure: %{"code" => 131_049}, chaos_tag: "async_fail:131049"} =
             Repo.get!(Message, msg.id)
  end

  test "webhook drop records the delivery as dropped without a job", %{waba: waba} do
    {:ok, _} = Chaos.update_profile(%{drop_rate: 1.0})
    {:ok, d} = Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}))
    assert %Delivery{state: "dropped", chaos_tag: "drop"} = d
    refute_enqueued(worker: Whelx.Webhooks.DeliveryWorker)
  end

  test "webhook duplicate creates two deliveries", %{waba: waba} do
    {:ok, _} = Chaos.update_profile(%{duplicate_rate: 1.0})

    {:ok, _} =
      Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}),
        message_wamid: "wamid.D"
      )

    assert [%{chaos_tag: "duplicate"}, %{chaos_tag: nil}] =
             Webhooks.list_deliveries(message_wamid: "wamid.D")
  end

  test "redeliver ignores chaos", %{waba: waba} do
    {:ok, d} =
      Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}),
        message_wamid: "wamid.R"
      )

    {:ok, _} = Chaos.update_profile(%{drop_rate: 1.0})
    {:ok, copy} = Webhooks.redeliver(d.id)
    assert copy.state == "pending"
  end

  test "batch merges pending statuses of the same number into one POST", %{
    phone: phone,
    waba: waba
  } do
    {:ok, _} = Chaos.update_profile(%{batch_rate: 1.0})

    status = fn id ->
      Payload.envelope(waba.id, "messages", %{
        "messaging_product" => "whatsapp",
        "metadata" => Payload.metadata(phone),
        "statuses" => [%{"id" => id, "status" => "sent"}]
      })
    end

    {:ok, a} = Webhooks.enqueue(waba.id, "statuses", status.("wamid.A"))
    {:ok, b} = Webhooks.enqueue(waba.id, "statuses", status.("wamid.B"))
    assert a.batch and b.batch

    test_pid = self()

    Req.Test.stub(Whelx.Webhooks.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:posted, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, "OK")
    end)

    :ok = Webhooks.attempt(Webhooks.get_delivery(a.id), 1)
    assert_received {:posted, payload}

    ids =
      payload
      |> get_in(["entry", Access.at(0), "changes", Access.at(0), "value", "statuses"])
      |> Enum.map(& &1["id"])

    assert ids == ["wamid.A", "wamid.B"]
    assert %{state: "merged", merged_into_id: merged} = Webhooks.get_delivery(b.id)
    assert merged == a.id
    assert Webhooks.get_delivery(a.id).chaos_tag == "batch:2"
  end

  test "reorder delays a status webhook", %{waba: waba} do
    {:ok, _} = Chaos.update_profile(%{reorder_rate: 1.0})

    {:ok, d} =
      Webhooks.enqueue(
        waba.id,
        "statuses",
        Payload.envelope(waba.id, "messages", %{"statuses" => []})
      )

    assert d.chaos_tag == "reorder"
    assert_enqueued(worker: Whelx.Webhooks.DeliveryWorker, args: %{"delivery_id" => d.id})
    [job] = all_enqueued(worker: Whelx.Webhooks.DeliveryWorker)
    assert DateTime.diff(job.scheduled_at, DateTime.utc_now(), :millisecond) > 1_500
  end

  test "same seed reproduces the same chaos decisions", %{waba: waba} do
    {:ok, _} = Chaos.update_profile(%{drop_rate: 0.5, seed: 99})

    run = fn ->
      Chaos.reset_counters()

      for _ <- 1..20 do
        {:ok, d} =
          Webhooks.enqueue(waba.id, "messages", Payload.envelope(waba.id, "messages", %{}))

        d.state
      end
    end

    assert run.() == run.()
  end
end
