defmodule WhelxWeb.ChatLiveTest do
  use WhelxWeb.ConnCase
  import Phoenix.LiveViewTest
  import Whelx.Fixtures
  alias Whelx.{Accounts, Contacts, Media, Messaging}
  alias Whelx.Graph.Validation
  alias Whelx.Messaging.{Message, Throughput}

  setup do
    Throughput.reset()
    {:ok, _} = Accounts.update_settings(%{sent_delay_ms: 0, delivered_delay_ms: 0})
    ctx = account_fixture()
    {:ok, contact} = Contacts.create_contact(%{wa_id: "5511977776666", profile_name: "Ana Souza"})
    Map.put(ctx, :contact, contact)
  end

  defp chat_path(phone, wa_id), do: ~p"/?#{[phone: phone.id, contact: wa_id]}"

  defp business_send(phone, type, content) do
    {:ok, req} =
      Validation.validate_send(%{
        "messaging_product" => "whatsapp",
        "to" => "5511977776666",
        "type" => type,
        type => content
      })

    {:ok, msg} = Messaging.send_outbound(phone, req)
    msg
  end

  test "lists contacts and opens a conversation", %{conn: conn, phone: phone} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Ana Souza"
    {:ok, _view, html} = live(conn, chat_path(phone, "5511977776666"))
    assert html =~ "Janela fechada"
  end

  test "sending text as the contact creates an inbound message", %{conn: conn, phone: phone} do
    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))
    view |> form("#composer", msg: %{text: "quero uma pizza"}) |> render_submit()

    assert [%Message{direction: "inbound", type: "text"} = msg] =
             Messaging.list_messages(%{"contact" => "5511977776666"})

    assert Message.content(msg) == %{"body" => "quero uma pizza"}
    assert render(view) =~ "quero uma pizza"
    assert render(view) =~ "Janela aberta"
  end

  test "business messages render live and buttons are clickable", %{conn: conn, phone: phone} do
    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))
    view |> form("#composer", msg: %{text: "oi"}) |> render_submit()

    business_send(phone, "interactive", %{
      "type" => "button",
      "body" => %{"text" => "Confirma o pedido?"},
      "action" => %{
        "buttons" => [
          %{"type" => "reply", "reply" => %{"id" => "confirm", "title" => "Confirmar"}}
        ]
      }
    })

    html = render(view)
    assert html =~ "Confirma o pedido?"
    assert html =~ "Confirmar"

    view |> element(~s(button[phx-click="reply"][phx-value-id="confirm"])) |> render_click()
    [last | _] = Messaging.list_messages(%{"contact" => "5511977776666"})

    assert %{"type" => "button_reply", "button_reply" => %{"id" => "confirm"}} =
             Message.content(last)
  end

  test "list, cta_url and order_details render", %{conn: conn, phone: phone} do
    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))
    view |> form("#composer", msg: %{text: "oi"}) |> render_submit()

    business_send(phone, "interactive", %{
      "type" => "list",
      "body" => %{"text" => "Cardápio"},
      "action" => %{
        "button" => "Ver sabores",
        "sections" => [
          %{
            "title" => "Pizzas",
            "rows" => [%{"id" => "calabresa", "title" => "Calabresa", "description" => "R$ 45"}]
          }
        ]
      }
    })

    business_send(phone, "interactive", %{
      "type" => "cta_url",
      "body" => %{"text" => "Acompanhe"},
      "action" => %{
        "name" => "cta_url",
        "parameters" => %{"display_text" => "Rastrear", "url" => "https://example.com/t/1"}
      }
    })

    business_send(phone, "interactive", %{
      "type" => "order_details",
      "body" => %{"text" => "Seu pedido"},
      "action" => %{
        "name" => "review_and_pay",
        "parameters" => %{
          "reference_id" => "o1",
          "type" => "physical-goods",
          "payment_type" => "br",
          "currency" => "BRL",
          "total_amount" => %{"value" => 4500, "offset" => 100},
          "order" => %{
            "status" => "pending",
            "items" => [
              %{
                "retailer_id" => "p1",
                "name" => "Calabresa",
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
                "code" => "00020126PIXCODE",
                "merchant_name" => "Pizzaria",
                "key" => "12345678000195",
                "key_type" => "CNPJ"
              }
            }
          ]
        }
      }
    })

    html = render(view)
    assert html =~ "Ver sabores"
    assert html =~ "Calabresa"
    assert html =~ "Rastrear"
    assert html =~ "R$ 45,00"
    assert html =~ "Copiar código Pix"

    view |> element(~s(button[phx-click="reply"][phx-value-id="calabresa"])) |> render_click()
    [last | _] = Messaging.list_messages(%{"contact" => "5511977776666"})

    assert %{"type" => "list_reply", "list_reply" => %{"id" => "calabresa"}} =
             Message.content(last)
  end

  test "templates render with quick replies", %{conn: conn, phone: phone, waba: waba} do
    approved_template_fixture(waba.id, %{
      "name" => "promo",
      "components" => [
        %{
          "type" => "BODY",
          "text" => "Oi {{1}}, promo!",
          "example" => %{"body_text" => [["Ana"]]}
        },
        %{"type" => "BUTTONS", "buttons" => [%{"type" => "QUICK_REPLY", "text" => "Quero"}]}
      ]
    })

    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))

    business_send(phone, "template", %{
      "name" => "promo",
      "language" => %{"code" => "pt_BR"},
      "components" => [
        %{"type" => "body", "parameters" => [%{"type" => "text", "text" => "Ana"}]}
      ]
    })

    html = render(view)
    assert html =~ "Oi Ana, promo!"
    view |> element(~s(button[phx-click="reply"][phx-value-id="0"])) |> render_click()
    [last | _] = Messaging.list_messages(%{"contact" => "5511977776666"})
    assert last.type == "button"
  end

  test "viewing the chat marks delivered business messages as read", %{conn: conn, phone: phone} do
    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))
    view |> form("#composer", msg: %{text: "oi"}) |> render_submit()
    msg = business_send(phone, "text", %{"body" => "Olá!"})
    Oban.drain_queue(queue: :statuses, with_scheduled: true, with_recursion: true)
    _ = render(view)
    assert Whelx.Repo.get!(Message, msg.id).status == "read"
  end

  test "location, reaction and audio recording", %{conn: conn, phone: phone} do
    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))

    view
    |> form("#location-form",
      loc: %{latitude: "-23.55", longitude: "-46.63", name: "Casa", address: "Rua A, 10"}
    )
    |> render_submit()

    [loc] = Messaging.list_messages(%{"contact" => "5511977776666"})
    assert %{"latitude" => -23.55, "name" => "Casa"} = Message.content(loc)

    out = business_send(phone, "text", %{"body" => "Pedido saiu"})
    render(view)

    view
    |> element(~s(button[phx-click="react"][phx-value-wamid="#{out.wamid}"][phx-value-emoji="👍"]))
    |> render_click()

    [reaction | _] =
      Messaging.list_messages(%{"contact" => "5511977776666", "type" => "reaction"})

    assert Message.content(reaction) == %{"message_id" => out.wamid, "emoji" => "👍"}

    render_hook(view, "audio_recorded", %{
      "data" => Base.encode64("OggS-voice"),
      "mime" => "audio/ogg;codecs=opus"
    })

    [audio | _] = Messaging.list_messages(%{"contact" => "5511977776666", "type" => "audio"})
    assert %{"voice" => true, "mime_type" => "audio/ogg; codecs=opus"} = Message.content(audio)
  end

  test "file upload sends an image", %{conn: conn, phone: phone} do
    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))

    file =
      file_input(view, "#upload-form", :media, [
        %{name: "cardapio.png", content: "PNGDATA", type: "image/png"}
      ])

    render_upload(file, "cardapio.png")
    view |> form("#upload-form") |> render_submit()
    [img] = Messaging.list_messages(%{"contact" => "5511977776666", "type" => "image"})
    assert %{"mime_type" => "image/png", "id" => id} = Message.content(img)
    assert {:ok, "PNGDATA"} = id |> Media.get_media() |> Media.read_binary()
  end

  test "inspector shows raw JSON and webhook deliveries", %{conn: conn, phone: phone} do
    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))
    view |> form("#composer", msg: %{text: "oi"}) |> render_submit()
    [msg] = Messaging.list_messages(%{"contact" => "5511977776666"})
    html = view |> element("#msg-#{msg.id} [phx-click=inspect]") |> render_click()
    assert html =~ msg.wamid
    assert html =~ "whatsapp_business_account"
  end

  test "expire window button closes the window", %{conn: conn, phone: phone} do
    {:ok, view, _} = live(conn, chat_path(phone, "5511977776666"))
    view |> form("#composer", msg: %{text: "oi"}) |> render_submit()
    html = view |> element("button", "Vencer janela") |> render_click()
    assert html =~ "Janela fechada"
  end

  test "media route serves stored files for the UI", %{conn: conn} do
    {:ok, media} = Media.store("IMG", "image/png")
    conn = get(conn, ~p"/ui/media/#{media.id}")
    assert response(conn, 200) == "IMG"
  end
end
