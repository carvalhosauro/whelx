defmodule Whelx.WaiterTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures
  alias Whelx.{Control, Messaging}
  alias Whelx.Control.Waiter
  alias Whelx.Graph.Validation
  alias Whelx.Messaging.Throughput

  setup do
    Throughput.reset()
    account_fixture()
  end

  defp reply(phone, text) do
    {:ok, req} =
      Validation.validate_send(%{
        "messaging_product" => "whatsapp",
        "to" => "5511977776666",
        "type" => "text",
        "text" => %{"body" => text}
      })

    {:ok, msg} = Messaging.send_outbound(phone, req)
    msg
  end

  test "outbound_message returns a reply that arrives after the wait started", %{phone: phone} do
    {:ok, inbound} = Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "oi"})

    Task.start(fn ->
      Process.sleep(100)
      reply(phone, "Olá! Qual pizza?")
    end)

    assert {:ok, %{"content" => %{"body" => "Olá! Qual pizza?"}, "direction" => "outbound"}} =
             Waiter.wait(%{
               "kind" => "outbound_message",
               "contact" => "5511977776666",
               "after" => inbound.wamid,
               "timeout_ms" => 2_000
             })
  end

  test "outbound_message returns immediately when the reply already exists after `after`", %{
    phone: phone
  } do
    {:ok, inbound} = Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "oi"})
    reply(phone, "já respondi")

    assert {:ok, %{"content" => %{"body" => "já respondi"}}} =
             Waiter.wait(%{
               "kind" => "outbound_message",
               "contact" => "5511977776666",
               "after" => inbound.wamid,
               "timeout_ms" => 100
             })
  end

  test "times out with the observed state" do
    assert {:timeout, %{"last_outbound" => nil}} =
             Waiter.wait(%{
               "kind" => "outbound_message",
               "contact" => "5511977776666",
               "timeout_ms" => 50
             })
  end

  test "status waits until a message reaches the status", %{phone: phone} do
    {:ok, _} = Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "oi"})
    msg = reply(phone, "ok")

    Task.start(fn ->
      Process.sleep(50)
      Messaging.transition(msg.id, "sent")
    end)

    assert {:ok, %{"status" => "sent"}} =
             Waiter.wait(%{
               "kind" => "status",
               "wamid" => msg.wamid,
               "status" => "sent",
               "timeout_ms" => 2_000
             })
  end

  test "webhook_delivery waits for the delivery state", %{} do
    {:ok, inbound} = Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "oi"})

    assert {:ok, %{"state" => "pending"}} =
             Waiter.wait(%{
               "kind" => "webhook_delivery",
               "message_wamid" => inbound.wamid,
               "state" => "pending",
               "timeout_ms" => 100
             })
  end

  test "invalid kind is an error" do
    assert {:error, _} = Waiter.wait(%{"kind" => "coffee"})
  end

  test "POST /_whelx/wait answers 200 or 408", %{conn: conn} do
    assert %{"observed" => _} =
             conn
             |> post("/_whelx/wait", %{
               "kind" => "outbound_message",
               "contact" => "5511977776666",
               "timeout_ms" => 50
             })
             |> json_response(408)
  end
end
