defmodule Whelx.E2EFlowTest do
  @moduledoc """
  Plays a client app against whelx end to end: signed webhooks in, Graph API calls
  out, status progression back in. Mirrors scripts/smoke.py without a server.
  """
  use WhelxWeb.ConnCase
  alias Whelx.{Accounts, Control}
  alias Whelx.Messaging.Throughput

  @phone "300000000000001"
  @waba "200000000000001"
  @token "EAAe2etoken"
  @secret "0123456789abcdef0123456789abcdef"
  @customer "5511988887777"

  setup do
    Throughput.reset()

    {:ok, _} =
      Control.seed(%{
        "app" => %{
          "app_id" => "100000000000001",
          "app_secret" => @secret,
          "verify_token" => "v",
          "webhook_url" => "http://app.test/webhooks/whatsapp"
        },
        "wabas" => [
          %{
            "id" => @waba,
            "name" => "Pizzaria",
            "subscribed" => true,
            "phone_numbers" => [
              %{
                "id" => @phone,
                "display_phone_number" => "+55 11 4000-1234",
                "verified_name" => "Pizzaria"
              }
            ]
          }
        ],
        "tokens" => [%{"token" => @token, "wabas" => [@waba]}],
        "contacts" => [
          %{
            "wa_id" => @customer,
            "profile_name" => "Ana",
            "read_policy" => "auto",
            "read_after_ms" => 0
          }
        ],
        "settings" => %{"sent_delay_ms" => 0, "delivered_delay_ms" => 0}
      })

    test_pid = self()

    Req.Test.stub(Whelx.Webhooks.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [signature] = Plug.Conn.get_req_header(conn, "x-hub-signature-256")

      expected =
        "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, @secret, body), case: :lower)

      send(test_pid, {:webhook, signature == expected, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, "OK")
    end)

    :ok
  end

  defp graph_post(path, body),
    do: build_conn() |> graph_auth(@token) |> post("/v25.0" <> path, body)

  defp deliver_all do
    Oban.drain_queue(queue: :statuses, with_scheduled: true, with_recursion: true)
    Oban.drain_queue(queue: :webhooks, with_scheduled: true)
    collect([])
  end

  defp collect(acc) do
    receive do
      {:webhook, signature_ok, payload} ->
        assert signature_ok, "invalid X-Hub-Signature-256"
        collect([payload | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp values(payloads, key),
    do:
      for(
        p <- payloads,
        e <- p["entry"],
        c <- e["changes"],
        v = c["value"][key],
        item <- v,
        do: item
      )

  test "order bot: greeting, menu, choice, Pix order and status progression" do
    {:ok, hi} =
      Control.send_as_contact(@customer, %{
        "type" => "text",
        "text" => "oi",
        "phone_number_id" => @phone
      })

    [incoming] = values(deliver_all(), "messages")
    assert incoming["id"] == hi.wamid
    assert incoming["text"] == %{"body" => "oi"}

    assert %{"success" => true} =
             graph_post("/#{@phone}/messages", %{
               "messaging_product" => "whatsapp",
               "status" => "read",
               "message_id" => hi.wamid,
               "typing_indicator" => %{"type" => "text"}
             })
             |> json_response(200)

    menu =
      graph_post("/#{@phone}/messages", %{
        "messaging_product" => "whatsapp",
        "to" => @customer,
        "type" => "interactive",
        "interactive" => %{
          "type" => "button",
          "body" => %{"text" => "Quer ver o cardápio?"},
          "action" => %{
            "buttons" => [
              %{"type" => "reply", "reply" => %{"id" => "menu", "title" => "Ver cardápio"}}
            ]
          }
        }
      })
      |> json_response(200)

    [%{"id" => menu_wamid}] = menu["messages"]

    statuses =
      values(deliver_all(), "statuses")
      |> Enum.filter(&(&1["id"] == menu_wamid))
      |> Enum.map(& &1["status"])

    assert statuses == ["sent", "delivered", "read"]

    {:ok, _} = Control.reply_interactive(@customer, menu_wamid, "menu")
    [click] = values(deliver_all(), "messages")

    assert click["interactive"] == %{
             "type" => "button_reply",
             "button_reply" => %{"id" => "menu", "title" => "Ver cardápio"}
           }

    assert click["context"]["id"] == menu_wamid

    order =
      graph_post("/#{@phone}/messages", %{
        "messaging_product" => "whatsapp",
        "to" => @customer,
        "type" => "interactive",
        "interactive" => %{
          "type" => "order_details",
          "body" => %{"text" => "Pedido #1"},
          "action" => %{
            "name" => "review_and_pay",
            "parameters" => %{
              "reference_id" => "1",
              "type" => "physical-goods",
              "payment_type" => "br",
              "currency" => "BRL",
              "total_amount" => %{"value" => 4500, "offset" => 100},
              "order" => %{
                "status" => "pending",
                "items" => [
                  %{
                    "retailer_id" => "p",
                    "name" => "Pizza",
                    "amount" => %{"value" => 4500, "offset" => 100},
                    "quantity" => 1
                  }
                ],
                "subtotal" => %{"value" => 4500, "offset" => 100}
              },
              "payment_settings" => [
                %{
                  "type" => "pix_dynamic_code",
                  "pix_dynamic_code" => %{
                    "code" => "000201",
                    "merchant_name" => "Pizzaria",
                    "key" => "12345678000195",
                    "key_type" => "CNPJ"
                  }
                }
              ]
            }
          }
        }
      })

    assert %{"messages" => [%{"id" => "wamid." <> _}]} = json_response(order, 200)
  end

  test "campaign: template created by the panel, approved in whelx, sent to many" do
    created =
      graph_post("/#{@waba}/message_templates", %{
        "name" => "crm_campaign_message",
        "language" => "pt_BR",
        "category" => "MARKETING",
        "components" => [
          %{"type" => "BODY", "text" => "Oi {{1}}", "example" => %{"body_text" => [["Ana"]]}}
        ]
      })
      |> json_response(200)

    assert created["status"] == "PENDING"
    {:ok, _} = Control.seed(%{"contacts" => []})
    {:ok, 30} = Whelx.Contacts.bulk_create(30)

    {:ok, _} = created["id"] |> Whelx.Templates.get_template() |> Whelx.Templates.approve()

    listing =
      build_conn()
      |> graph_auth(@token)
      |> get("/v25.0/#{@waba}/message_templates?fields=name,status&limit=100")
      |> json_response(200)

    assert [%{"name" => "crm_campaign_message", "status" => "APPROVED"}] = listing["data"]

    recipients =
      Whelx.Contacts.list_contacts() |> Enum.map(& &1.wa_id) |> Enum.reject(&(&1 == @customer))

    wamids =
      for to <- recipients do
        %{"messages" => [%{"id" => id, "message_status" => "accepted"}]} =
          graph_post("/#{@phone}/messages", %{
            "messaging_product" => "whatsapp",
            "to" => to,
            "type" => "template",
            "template" => %{
              "name" => "crm_campaign_message",
              "language" => %{"code" => "pt_BR"},
              "components" => [
                %{"type" => "body", "parameters" => [%{"type" => "text", "text" => "Ana"}]}
              ]
            }
          })
          |> json_response(200)

        id
      end

    statuses = values(deliver_all(), "statuses")
    delivered = statuses |> Enum.filter(&(&1["status"] == "delivered")) |> MapSet.new(& &1["id"])
    assert MapSet.equal?(delivered, MapSet.new(wamids))

    assert Enum.all?(
             statuses,
             &(&1["pricing"]["category"] == "marketing" and &1["pricing"]["billable"])
           )

    assert Accounts.get_settings().template_approval_policy == "manual"
  end
end
