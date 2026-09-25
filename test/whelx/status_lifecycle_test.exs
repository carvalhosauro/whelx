defmodule Whelx.StatusLifecycleTest do
  use Whelx.DataCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Contacts, Messaging, Repo, Webhooks}
  alias Whelx.Graph.Validation
  alias Whelx.Messaging.{Message, StatusWorker, Throughput}

  setup do
    Throughput.reset()
    {:ok, _} = Accounts.update_settings(%{sent_delay_ms: 0, delivered_delay_ms: 0})
    account_fixture()
  end

  defp open_window(phone, wa_id) do
    {:ok, _} =
      Messaging.receive_inbound(phone.id, wa_id, %{
        type: "text",
        content: %{"body" => "oi"},
        context_wamid: nil
      })
  end

  defp send_text(phone, wa_id) do
    {:ok, req} =
      Validation.validate_send(%{
        "messaging_product" => "whatsapp",
        "to" => wa_id,
        "type" => "text",
        "text" => %{"body" => "olá"}
      })

    {:ok, msg} = Messaging.send_outbound(phone, req)
    msg
  end

  defp drain, do: Oban.drain_queue(queue: :statuses, with_scheduled: true, with_recursion: true)

  defp status_webhooks(wamid) do
    Webhooks.list_deliveries(message_wamid: wamid)
    |> Enum.filter(&(&1.kind == "statuses"))
    |> Enum.sort_by(& &1.id)
    |> Enum.map(
      &hd(
        get_in(&1.payload, ["entry", Access.at(0), "changes", Access.at(0), "value", "statuses"])
      )
    )
  end

  test "online contact progresses accepted → sent → delivered and stops (on_open)", %{
    phone: phone
  } do
    open_window(phone, "5511977776666")
    msg = send_text(phone, "5511977776666")
    drain()

    assert %Message{status: "delivered", sent_at: %DateTime{}, delivered_at: %DateTime{}} =
             Repo.get!(Message, msg.id)

    [sent, delivered] = status_webhooks(msg.wamid)

    assert %{
             "id" => wamid,
             "status" => "sent",
             "recipient_id" => "5511977776666",
             "timestamp" => ts,
             "pricing" => %{
               "billable" => false,
               "pricing_model" => "PMP",
               "type" => "free_customer_service",
               "category" => "service"
             }
           } = sent

    assert wamid == msg.wamid
    assert ts =~ ~r/^\d{10}$/
    refute Map.has_key?(sent, "conversation")
    assert delivered["status"] == "delivered"
  end

  test "status envelope carries metadata of the business number", %{phone: phone, waba: waba} do
    open_window(phone, "5511977776666")
    msg = send_text(phone, "5511977776666")
    drain()

    [delivery | _] =
      Webhooks.list_deliveries(message_wamid: msg.wamid) |> Enum.filter(&(&1.kind == "statuses"))

    assert %{
             "object" => "whatsapp_business_account",
             "entry" => [%{"id" => id, "changes" => [%{"field" => "messages", "value" => value}]}]
           } = delivery.payload

    assert id == waba.id
    assert value["messaging_product"] == "whatsapp"

    assert value["metadata"] == %{
             "display_phone_number" => "551140000001",
             "phone_number_id" => phone.id
           }
  end

  test "offline contact holds at sent until it comes online", %{phone: phone} do
    {:ok, contact} = Contacts.create_contact(%{wa_id: "5511977776666", online: false})
    open_window(phone, contact.wa_id)
    msg = send_text(phone, contact.wa_id)
    drain()
    assert Repo.get!(Message, msg.id).status == "sent"

    {:ok, _} = Messaging.set_contact_online(contact, true)
    drain()
    assert Repo.get!(Message, msg.id).status == "delivered"
  end

  test "auto read policy reads after delivery", %{phone: phone} do
    {:ok, _} =
      Contacts.create_contact(%{wa_id: "5511977776666", read_policy: "auto", read_after_ms: 0})

    open_window(phone, "5511977776666")
    msg = send_text(phone, "5511977776666")
    drain()
    assert Repo.get!(Message, msg.id).status == "read"
    assert Enum.map(status_webhooks(msg.wamid), & &1["status"]) == ~w(sent delivered read)
  end

  test "open_conversation/1 reads delivered messages for on_open contacts", %{phone: phone} do
    open_window(phone, "5511977776666")
    msg = send_text(phone, "5511977776666")
    drain()
    :ok = Messaging.open_conversation(msg.conversation_id)
    assert Repo.get!(Message, msg.id).status == "read"
    assert Messaging.get_conversation!(msg.conversation_id).unread_count == 0
  end

  test "never policy does not read", %{phone: phone} do
    {:ok, _} = Contacts.create_contact(%{wa_id: "5511977776666", read_policy: "never"})
    open_window(phone, "5511977776666")
    msg = send_text(phone, "5511977776666")
    drain()
    :ok = Messaging.open_conversation(msg.conversation_id)
    assert Repo.get!(Message, msg.id).status == "delivered"
  end

  test "planned failure goes straight to failed with Meta's error object", %{phone: phone} do
    msg = send_text(phone, "5511977776666")
    drain()
    assert %Message{status: "failed", errors: [%{"code" => 131_047}]} = Repo.get!(Message, msg.id)
    [failed] = status_webhooks(msg.wamid)

    assert %{
             "status" => "failed",
             "errors" => [
               %{
                 "code" => 131_047,
                 "title" => "Re-engagement message",
                 "message" => "Re-engagement message",
                 "error_data" => %{"details" => _},
                 "href" => "/documentation/business-messaging/whatsapp/support/error-codes"
               }
             ]
           } = failed

    refute Map.has_key?(failed, "pricing")
  end

  test "transitions only move forward" do
    assert Messaging.allowed_transition?("accepted", "sent")
    assert Messaging.allowed_transition?("sent", "failed")
    refute Messaging.allowed_transition?("read", "sent")
    refute Messaging.allowed_transition?("failed", "delivered")
    refute Messaging.allowed_transition?("delivered", "failed")
  end

  test "worker is a no-op when the message was reset away" do
    assert :ok = perform_job(StatusWorker, %{"message_id" => -1, "status" => "sent"})
  end
end
