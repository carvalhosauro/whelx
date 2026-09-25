defmodule Whelx.MessagingInboundTest do
  use Whelx.DataCase
  import Whelx.Fixtures
  alias Whelx.{Messaging, Webhooks}

  setup do
    account_fixture()
  end

  test "receive_inbound/3 stores the message, opens the window and queues the webhook",
       %{phone: phone, waba: waba} do
    Whelx.Events.subscribe("messages")

    {:ok, msg} =
      Messaging.receive_inbound(phone.id, "5511977776666", %{
        type: "text",
        content: %{"body" => "oi"},
        context_wamid: nil
      })

    assert msg.direction == "inbound"
    assert msg.status == "received"
    assert String.starts_with?(msg.wamid, "wamid.")
    assert_receive {:message_created, %{id: id}} when id == msg.id

    conv = Messaging.get_conversation!(msg.conversation_id)
    assert Messaging.window_open?(conv)
    assert DateTime.diff(conv.window_expires_at, DateTime.utc_now(), :hour) in 23..24

    [delivery] = Webhooks.list_deliveries()
    assert delivery.kind == "messages"
    assert delivery.message_wamid == msg.wamid

    assert %{
             "object" => "whatsapp_business_account",
             "entry" => [
               %{"id" => waba_id, "changes" => [%{"field" => "messages", "value" => value}]}
             ]
           } = delivery.payload

    assert waba_id == waba.id

    assert value == %{
             "messaging_product" => "whatsapp",
             "metadata" => %{
               "display_phone_number" => "551140000001",
               "phone_number_id" => phone.id
             },
             "contacts" => [
               %{"profile" => %{"name" => conv.contact.profile_name}, "wa_id" => "5511977776666"}
             ],
             "messages" => [
               %{
                 "from" => "5511977776666",
                 "id" => msg.wamid,
                 "timestamp" => Whelx.Attrs.unix(msg.inserted_at),
                 "type" => "text",
                 "text" => %{"body" => "oi"}
               }
             ]
           }
  end

  test "context is included when replying to a business message", %{phone: phone} do
    {:ok, msg} =
      Messaging.receive_inbound(phone.id, "5511977776666", %{
        type: "interactive",
        content: %{"type" => "button_reply", "button_reply" => %{"id" => "b1", "title" => "Sim"}},
        context_wamid: "wamid.ORIGINAL"
      })

    [delivery] = Webhooks.list_deliveries()

    [message] =
      get_in(delivery.payload, [
        "entry",
        Access.at(0),
        "changes",
        Access.at(0),
        "value",
        "messages"
      ])

    assert message["context"] == %{"from" => "551140000001", "id" => "wamid.ORIGINAL"}
    assert message["interactive"]["button_reply"] == %{"id" => "b1", "title" => "Sim"}
    assert msg.context_wamid == "wamid.ORIGINAL"
  end

  test "expire_window/1 closes the 24h window", %{phone: phone} do
    {:ok, msg} =
      Messaging.receive_inbound(phone.id, "5511977776666", %{
        type: "text",
        content: %{"body" => "oi"},
        context_wamid: nil
      })

    conv = Messaging.get_conversation!(msg.conversation_id)
    {:ok, conv} = Messaging.expire_window(conv)
    refute Messaging.window_open?(conv)
  end

  test "get_or_create_conversation/2 is unique per phone and contact", %{phone: phone} do
    Whelx.Contacts.find_or_create_contact("5511977776666")
    a = Messaging.get_or_create_conversation(phone.id, "5511977776666")
    b = Messaging.get_or_create_conversation(phone.id, "5511977776666")
    assert a.id == b.id
  end
end
