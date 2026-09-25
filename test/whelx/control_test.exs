defmodule Whelx.ControlTest do
  use Whelx.DataCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Contacts, Control, Messaging, Repo, Templates, Webhooks}
  alias Whelx.Graph.Validation
  alias Whelx.Messaging.{Message, Throughput}

  setup do
    Throughput.reset()
    :ok
  end

  @seed %{
    "app" => %{
      "app_id" => "111111111111111",
      "app_secret" => "0123456789abcdef0123456789abcdef",
      "verify_token" => "verify-me",
      "webhook_url" => "http://pigz.test/api/webhook/whatsapp"
    },
    "wabas" => [
      %{
        "id" => "222222222222222",
        "name" => "Pizzaria",
        "subscribed" => true,
        "phone_numbers" => [
          %{
            "id" => "333333333333333",
            "display_phone_number" => "+55 11 4000-0001",
            "verified_name" => "Pizzaria"
          }
        ]
      }
    ],
    "tokens" => [%{"token" => "EAAwhelxTestToken", "wabas" => "all"}],
    "contacts" => [%{"wa_id" => "5511977776666", "profile_name" => "Ana"}],
    "templates" => [
      %{
        "waba_id" => "222222222222222",
        "name" => "crm_campaign_message",
        "language" => "pt_BR",
        "category" => "MARKETING",
        "components" => [
          %{"type" => "BODY", "text" => "Oi {{1}}", "example" => %{"body_text" => [["Ana"]]}}
        ]
      }
    ]
  }

  test "seed/1 creates the scenario and is idempotent" do
    {:ok, snap} = Control.seed(@seed)
    {:ok, _} = Control.seed(@seed)

    assert snap["app"]["app_id"] == "111111111111111"
    assert snap["app"]["app_secret"] == "0123456789abcdef0123456789abcdef"

    assert [%{"id" => "222222222222222", "phone_numbers" => [%{"id" => "333333333333333"}]}] =
             snap["wabas"]

    assert [%{"token" => "EAAwhelxTestToken", "waba_ids" => ["222222222222222"]}] = snap["tokens"]
    assert length(Contacts.list_contacts()) == 1
    assert [%{status: "APPROVED"}] = Templates.list_all()
    assert length(Accounts.list_wabas()) == 1
  end

  test "seed/1 rolls back on invalid data" do
    bad = put_in(@seed, ["tokens"], [%{"token" => "nope", "wabas" => "all"}])
    assert {:error, _} = Control.seed(bad)
    assert Accounts.list_wabas() == []
  end

  test "env_block/0 lists the pigz-api variables" do
    {:ok, _} = Control.seed(@seed)
    block = Control.env_block()
    assert block =~ "META_APP_ID=111111111111111"
    assert block =~ "META_APP_SECRET=0123456789abcdef0123456789abcdef"
    assert block =~ "META_GRAPH_BASE_URL=http://whelx.test"
    assert block =~ "META_GRAPH_API_VERSION=v25.0"
    assert block =~ "WHATSAPP_WEBHOOK_VERIFY_TOKEN=verify-me"
  end

  describe "with an account" do
    setup do
      account_fixture()
    end

    test "send_as_contact/2 supports text, location, reaction and media", %{phone: phone} do
      {:ok, text} =
        Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "quero pizza"})

      assert Message.content(text) == %{"body" => "quero pizza"}

      {:ok, loc} =
        Control.send_as_contact("5511977776666", %{
          "type" => "location",
          "latitude" => -23.5,
          "longitude" => -46.6,
          "name" => "Casa",
          "address" => "Rua A, 1"
        })

      assert Message.content(loc) == %{
               "latitude" => -23.5,
               "longitude" => -46.6,
               "name" => "Casa",
               "address" => "Rua A, 1"
             }

      {:ok, reaction} =
        Control.send_as_contact("5511977776666", %{
          "type" => "reaction",
          "message_id" => text.wamid,
          "emoji" => "👍"
        })

      assert Message.content(reaction) == %{"message_id" => text.wamid, "emoji" => "👍"}

      {:ok, audio} =
        Control.send_as_contact("5511977776666", %{
          "type" => "audio",
          "media_base64" => Base.encode64("OggS"),
          "mime_type" => "audio/ogg; codecs=opus",
          "phone_number_id" => phone.id
        })

      assert %{"voice" => true, "id" => _} = Message.content(audio)

      assert {:error, "tipo não suportado: sticker"} =
               Control.send_as_contact("5511977776666", %{"type" => "sticker"})

      assert {:error, _} =
               Control.send_as_contact("5511977776666", %{
                 "type" => "audio",
                 "media_base64" => "%%%"
               })
    end

    test "reply_interactive/3 clicks buttons, list rows and template quick replies", %{
      phone: phone,
      waba: waba
    } do
      {:ok, _} = Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "oi"})

      send = fn type, content ->
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

      buttons =
        send.("interactive", %{
          "type" => "button",
          "body" => %{"text" => "Confirma?"},
          "action" => %{
            "buttons" => [%{"type" => "reply", "reply" => %{"id" => "yes", "title" => "Sim"}}]
          }
        })

      {:ok, reply} = Control.reply_interactive("5511977776666", buttons.wamid, "yes")
      assert reply.type == "interactive"
      assert reply.context_wamid == buttons.wamid

      assert Message.content(reply) == %{
               "type" => "button_reply",
               "button_reply" => %{"id" => "yes", "title" => "Sim"}
             }

      list =
        send.("interactive", %{
          "type" => "list",
          "body" => %{"text" => "Cardápio"},
          "action" => %{
            "button" => "Ver",
            "sections" => [
              %{
                "title" => "Pizzas",
                "rows" => [%{"id" => "p1", "title" => "Calabresa", "description" => "Grande"}]
              }
            ]
          }
        })

      {:ok, reply} = Control.reply_interactive("5511977776666", list.wamid, "p1")

      assert Message.content(reply) == %{
               "type" => "list_reply",
               "list_reply" => %{"id" => "p1", "title" => "Calabresa", "description" => "Grande"}
             }

      approved_template_fixture(waba.id, %{
        "name" => "reward_join",
        "category" => "UTILITY",
        "components" => [
          %{"type" => "BODY", "text" => "Participar?"},
          %{"type" => "BUTTONS", "buttons" => [%{"type" => "QUICK_REPLY", "text" => "Sim"}]}
        ]
      })

      tpl =
        send.("template", %{
          "name" => "reward_join",
          "language" => %{"code" => "pt_BR"},
          "components" => [
            %{
              "type" => "button",
              "sub_type" => "quick_reply",
              "index" => "0",
              "parameters" => [%{"type" => "payload", "payload" => "reward_join:yes:tok"}]
            }
          ]
        })

      {:ok, reply} = Control.reply_interactive("5511977776666", tpl.wamid, "0")
      assert reply.type == "button"
      assert Message.content(reply) == %{"payload" => "reward_join:yes:tok", "text" => "Sim"}

      assert {:error, _} = Control.reply_interactive("5511977776666", buttons.wamid, "nope")
      assert {:error, _} = Control.reply_interactive("5511900000000", buttons.wamid, "yes")

      assert {:error, :not_found} =
               Control.reply_interactive("5511977776666", "wamid.unknown", "yes")
    end

    test "reset/1 clears test data, keeps config and cancels jobs", %{waba: waba} do
      {:ok, _} = Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "oi"})
      approved_template_fixture(waba.id)
      assert Webhooks.list_deliveries() != []

      :ok = Control.reset(["templates"])
      assert Repo.all(Message) == []
      assert Webhooks.list_deliveries() == []
      assert Contacts.list_contacts() == []
      assert [_] = Templates.list_all()
      assert [_] = Accounts.list_wabas()
      assert Repo.all(Oban.Job) |> Enum.all?(&(&1.state == "cancelled"))

      {:ok, _} = Control.send_as_contact("5511977776666", %{"type" => "text", "text" => "oi"})
      :ok = Control.reset(["contacts"])
      assert [_] = Contacts.list_contacts()
      assert Templates.list_all() == []
    end
  end
end
