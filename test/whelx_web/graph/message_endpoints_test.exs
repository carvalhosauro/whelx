defmodule WhelxWeb.Graph.MessageEndpointsTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Contacts, Messaging}
  alias Whelx.Messaging.{Message, Throughput}

  setup do
    Throughput.reset()
    account_fixture()
  end

  defp send_msg(conn, token, phone, body),
    do: conn |> graph_auth(token) |> post("/v25.0/#{phone.id}/messages", body)

  defp text_body(to \\ "5511977776666", text \\ "Olá!"),
    do: %{
      "messaging_product" => "whatsapp",
      "recipient_type" => "individual",
      "to" => to,
      "type" => "text",
      "text" => %{"preview_url" => false, "body" => text}
    }

  defp open_window(phone, wa_id \\ "5511977776666") do
    {:ok, msg} =
      Messaging.receive_inbound(phone.id, wa_id, %{
        type: "text",
        content: %{"body" => "oi"},
        context_wamid: nil
      })

    msg
  end

  test "text inside the window answers exactly like Meta", %{
    conn: conn,
    token: token,
    phone: phone
  } do
    open_window(phone)
    conn = send_msg(conn, token, phone, text_body())

    assert %{
             "messaging_product" => "whatsapp",
             "contacts" => [%{"input" => "5511977776666", "wa_id" => "5511977776666"}],
             "messages" => [%{"id" => wamid} = m]
           } =
             json_response(conn, 200)

    refute Map.has_key?(m, "message_status")

    assert %Message{direction: "outbound", status: "accepted", planned_failure: nil, type: "text"} =
             Messaging.get_message_by_wamid(wamid)
  end

  test "formatted recipient is normalized while input is echoed", %{
    conn: conn,
    token: token,
    phone: phone
  } do
    conn = send_msg(conn, token, phone, text_body("+55 (11) 96666-5555"))

    assert %{"contacts" => [%{"input" => "+55 (11) 96666-5555", "wa_id" => "5511966665555"}]} =
             json_response(conn, 200)

    assert Contacts.get_contact("5511966665555")
  end

  test "text outside the window is accepted and planned to fail with 131047", %{
    conn: conn,
    token: token,
    phone: phone
  } do
    conn = send_msg(conn, token, phone, text_body())
    %{"messages" => [%{"id" => wamid}]} = json_response(conn, 200)
    assert %Message{planned_failure: %{"code" => 131_047}} = Messaging.get_message_by_wamid(wamid)
  end

  test "invalid_number and blocked contacts are planned to fail with 131026", %{
    conn: conn,
    token: token,
    phone: phone
  } do
    {:ok, _} = Contacts.create_contact(%{wa_id: "5511955554444", behavior: "invalid_number"})
    {:ok, _} = Contacts.create_contact(%{wa_id: "5511955553333", behavior: "blocked"})
    open_window(phone, "5511955554444")
    open_window(phone, "5511955553333")

    for to <- ["5511955554444", "5511955553333"] do
      %{"messages" => [%{"id" => wamid}]} =
        json_response(send_msg(build_conn(), token, phone, text_body(to)), 200)

      assert %Message{planned_failure: %{"code" => 131_026}} =
               Messaging.get_message_by_wamid(wamid)
    end

    _ = conn
  end

  test "template send returns message_status accepted and stores the rendering", %{
    conn: conn,
    token: token,
    phone: phone,
    waba: waba
  } do
    approved_template_fixture(waba.id)

    body = %{
      "messaging_product" => "whatsapp",
      "recipient_type" => "individual",
      "to" => "5511977776666",
      "type" => "template",
      "template" => %{
        "name" => "crm_campaign_message",
        "language" => %{"code" => "pt_BR"},
        "components" => [
          %{
            "type" => "body",
            "parameters" => [
              %{"type" => "text", "text" => "Pizzaria"},
              %{"type" => "text", "text" => "Promo"}
            ]
          }
        ]
      }
    }

    %{"messages" => [%{"id" => wamid, "message_status" => "accepted"}]} =
      json_response(send_msg(conn, token, phone, body), 200)

    msg = Messaging.get_message_by_wamid(wamid)
    assert msg.planned_failure == nil
    assert msg.payload["rendered"]["body"] =~ "Mensagem de *Pizzaria*"
    assert msg.payload["category"] == "marketing"
  end

  test "template errors: 132001 and 132000", %{conn: conn, token: token, phone: phone, waba: waba} do
    body = fn components ->
      %{
        "messaging_product" => "whatsapp",
        "to" => "5511977776666",
        "type" => "template",
        "template" => %{
          "name" => "crm_campaign_message",
          "language" => %{"code" => "pt_BR"},
          "components" => components
        }
      }
    end

    assert %{"error" => %{"code" => 132_001, "error_data" => %{"details" => _}}} =
             json_response(send_msg(conn, token, phone, body.([])), 404)

    approved_template_fixture(waba.id)

    assert %{"error" => %{"code" => 132_000}} =
             json_response(send_msg(build_conn(), token, phone, body.([])), 400)
  end

  test "throughput per phone returns 130429", %{token: token, phone: phone} do
    {:ok, phone} = Accounts.upsert_phone_number(%{id: phone.id, throughput_mps: 1})
    statuses = for _ <- 1..5, do: send_msg(build_conn(), token, phone, text_body()).status
    assert 400 in statuses

    conn =
      Enum.find_value(1..5, fn _ ->
        c = send_msg(build_conn(), token, phone, text_body())
        if c.status == 400, do: c
      end)

    assert %{"error" => %{"code" => 130_429}} = json_response(conn, 400)
  end

  test "unsupported outbound types fail loudly", %{conn: conn, token: token, phone: phone} do
    body = %{
      "messaging_product" => "whatsapp",
      "to" => "5511977776666",
      "type" => "image",
      "image" => %{"link" => "https://x/y.png"}
    }

    assert %{"error" => %{"code" => 100, "error_user_msg" => "whelx: não suportado" <> _}} =
             json_response(send_msg(conn, token, phone, body), 400)
  end

  test "read receipt with typing indicator marks inbound read and shows typing", %{
    conn: conn,
    token: token,
    phone: phone
  } do
    older = open_window(phone)
    inbound = open_window(phone)

    body = %{
      "messaging_product" => "whatsapp",
      "status" => "read",
      "message_id" => inbound.wamid,
      "typing_indicator" => %{"type" => "text"}
    }

    assert json_response(send_msg(conn, token, phone, body), 200) == %{"success" => true}
    assert %{status: "read"} = Messaging.get_message_by_wamid(inbound.wamid)
    assert %{status: "read"} = Messaging.get_message_by_wamid(older.wamid)
    conv = Messaging.get_conversation!(inbound.conversation_id)
    assert DateTime.after?(conv.typing_until, DateTime.utc_now())
  end

  test "read receipt for an unknown message id is code 100", %{
    conn: conn,
    token: token,
    phone: phone
  } do
    body = %{"messaging_product" => "whatsapp", "status" => "read", "message_id" => "wamid.nope"}
    assert %{"error" => %{"code" => 100}} = json_response(send_msg(conn, token, phone, body), 400)
  end

  test "phone of a waba the token cannot access is forbidden", %{conn: conn} do
    {:ok, other} = Accounts.upsert_waba(%{name: "Outra"})
    {:ok, token} = Accounts.create_token([other.id])
    %{phone: phone} = %{phone: hd(Accounts.list_all_phone_numbers())}

    assert %{"error" => %{"code" => 200}} =
             json_response(send_msg(conn, token.token, phone, text_body()), 403)
  end

  test "outbound message clears typing and bumps the conversation", %{
    conn: conn,
    token: token,
    phone: phone
  } do
    inbound = open_window(phone)

    send_msg(conn, token, phone, %{
      "messaging_product" => "whatsapp",
      "status" => "read",
      "message_id" => inbound.wamid,
      "typing_indicator" => %{"type" => "text"}
    })

    send_msg(build_conn(), token, phone, text_body())
    assert Messaging.get_conversation!(inbound.conversation_id).typing_until == nil
  end
end
