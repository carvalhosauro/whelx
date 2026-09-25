defmodule Whelx.Graph.ValidationTest do
  use ExUnit.Case, async: true
  alias Whelx.Graph.{Error, Validation}

  defp msg(type, content, extra \\ %{}) do
    Map.merge(
      %{
        "messaging_product" => "whatsapp",
        "recipient_type" => "individual",
        "to" => "5511999990000",
        "type" => type,
        type => content
      },
      extra
    )
  end

  defp user_msg({:error, %Error{code: 100, user_msg: m}}), do: m

  describe "validate_send/1 envelope" do
    test "accepts text and normalizes the recipient" do
      assert {:ok,
              %{
                kind: :message,
                to: "5511999990000",
                to_input: "+55 (11) 99999-0000",
                type: "text",
                content: %{"body" => "oi"},
                context_wamid: "wamid.X"
              }} =
               Validation.validate_send(
                 msg("text", %{"body" => "oi"}, %{
                   "to" => "+55 (11) 99999-0000",
                   "context" => %{"message_id" => "wamid.X"}
                 })
               )
    end

    test "rejects wrong messaging_product and bad recipients" do
      assert user_msg(
               Validation.validate_send(
                 msg("text", %{"body" => "oi"}, %{"messaging_product" => "sms"})
               )
             ) =~ "messaging_product"

      assert user_msg(Validation.validate_send(msg("text", %{"body" => "oi"}, %{"to" => "12"}))) =~
               "to"
    end

    test "flags known but unsupported types as whelx gaps" do
      assert {:error, %Error{code: 100, user_msg: "whelx: not supported" <> _}} =
               Validation.validate_send(msg("image", %{"link" => "http://x"}))
    end

    test "rejects unknown types and missing objects" do
      assert user_msg(Validation.validate_send(msg("hologram", %{}))) =~ "type"

      assert user_msg(
               Validation.validate_send(%{
                 "messaging_product" => "whatsapp",
                 "to" => "5511999990000",
                 "type" => "text"
               })
             ) =~ "text"
    end

    test "text body is required and limited to 4096 chars" do
      assert user_msg(Validation.validate_send(msg("text", %{"body" => ""}))) =~ "body"

      assert user_msg(
               Validation.validate_send(msg("text", %{"body" => String.duplicate("a", 4097)}))
             ) =~ "4096"
    end

    test "read receipt with typing indicator" do
      assert {:ok, %{kind: :read, message_id: "wamid.A", typing: true}} =
               Validation.validate_send(%{
                 "messaging_product" => "whatsapp",
                 "status" => "read",
                 "message_id" => "wamid.A",
                 "typing_indicator" => %{"type" => "text"}
               })

      assert {:ok, %{typing: false}} =
               Validation.validate_send(%{
                 "messaging_product" => "whatsapp",
                 "status" => "read",
                 "message_id" => "wamid.A"
               })
    end
  end

  describe "template payload" do
    test "requires name and language.code" do
      assert {:ok, _} =
               Validation.validate_send(
                 msg("template", %{"name" => "promo", "language" => %{"code" => "pt_BR"}})
               )

      assert user_msg(Validation.validate_send(msg("template", %{"name" => "promo"}))) =~ "code"
    end

    test "validates components and button sub_type" do
      ok = %{
        "name" => "promo",
        "language" => %{"code" => "pt_BR"},
        "components" => [
          %{"type" => "body", "parameters" => [%{"type" => "text", "text" => "Ana"}]},
          %{
            "type" => "button",
            "sub_type" => "quick_reply",
            "index" => "0",
            "parameters" => [%{"type" => "payload", "payload" => "yes"}]
          }
        ]
      }

      assert {:ok, _} = Validation.validate_send(msg("template", ok))
      bad = put_in(ok, ["components", Access.at(1), "sub_type"], "mystery")
      assert user_msg(Validation.validate_send(msg("template", bad))) =~ "sub_type"
    end
  end

  describe "interactive" do
    defp button(n),
      do: %{"type" => "reply", "reply" => %{"id" => "b#{n}", "title" => "Opção #{n}"}}

    test "button: 1 to 3 unique buttons with titles up to 20 chars" do
      base = %{
        "type" => "button",
        "body" => %{"text" => "Escolha"},
        "action" => %{"buttons" => [button(1), button(2)]}
      }

      assert {:ok, _} = Validation.validate_send(msg("interactive", base))

      assert user_msg(
               Validation.validate_send(
                 msg(
                   "interactive",
                   put_in(base, ["action", "buttons"], Enum.map(1..4, &button/1))
                 )
               )
             ) =~ "1 to 3"

      long =
        put_in(base, ["action", "buttons"], [
          %{"type" => "reply", "reply" => %{"id" => "x", "title" => String.duplicate("a", 21)}}
        ])

      assert user_msg(Validation.validate_send(msg("interactive", long))) =~ "20"
      dup = put_in(base, ["action", "buttons"], [button(1), button(1)])
      assert user_msg(Validation.validate_send(msg("interactive", dup))) =~ "duplicate ids"
    end

    test "list: sections and row limits" do
      rows = fn n -> Enum.map(1..n, &%{"id" => "r#{&1}", "title" => "Item #{&1}"}) end

      base = %{
        "type" => "list",
        "body" => %{"text" => "Cardápio"},
        "action" => %{
          "button" => "Ver",
          "sections" => [%{"title" => "Pizzas", "rows" => rows.(3)}]
        }
      }

      assert {:ok, _} = Validation.validate_send(msg("interactive", base))

      assert user_msg(
               Validation.validate_send(
                 msg(
                   "interactive",
                   put_in(base, ["action", "sections"], [%{"title" => "A", "rows" => rows.(11)}])
                 )
               )
             ) =~ "total rows"

      long_row =
        put_in(base, ["action", "sections"], [
          %{"rows" => [%{"id" => "r", "title" => String.duplicate("x", 25)}]}
        ])

      assert user_msg(Validation.validate_send(msg("interactive", long_row))) =~ "24"

      two_untitled =
        put_in(base, ["action", "sections"], [%{"rows" => rows.(1)}, %{"rows" => rows.(1)}])

      assert user_msg(Validation.validate_send(msg("interactive", two_untitled))) =~ "title"
    end

    test "cta_url: display_text and url" do
      base = %{
        "type" => "cta_url",
        "body" => %{"text" => "Acompanhe"},
        "action" => %{
          "name" => "cta_url",
          "parameters" => %{"display_text" => "Abrir", "url" => "https://example.com/p/1"}
        }
      }

      assert {:ok, _} = Validation.validate_send(msg("interactive", base))

      assert user_msg(
               Validation.validate_send(
                 msg("interactive", put_in(base, ["action", "parameters", "url"], "nope"))
               )
             ) =~ "url"
    end

    defp order(overrides \\ %{}) do
      params =
        Map.merge(
          %{
            "reference_id" => "order-123",
            "type" => "physical-goods",
            "payment_type" => "br",
            "currency" => "BRL",
            "total_amount" => %{"value" => 5500, "offset" => 100},
            "order" => %{
              "status" => "pending",
              "items" => [
                %{
                  "retailer_id" => "sku1",
                  "name" => "Pizza",
                  "amount" => %{"value" => 2000, "offset" => 100},
                  "quantity" => 2
                },
                %{
                  "retailer_id" => "sku2",
                  "name" => "Refri",
                  "amount" => %{"value" => 1000, "offset" => 100},
                  "quantity" => 1
                }
              ],
              "subtotal" => %{"value" => 5000, "offset" => 100},
              "tax" => %{"value" => 500, "offset" => 100, "description" => "Taxa de entrega"}
            },
            "payment_settings" => [
              %{
                "type" => "pix_dynamic_code",
                "pix_dynamic_code" => %{
                  "code" => "000201...",
                  "merchant_name" => "Pizzaria",
                  "key" => "12345678000195",
                  "key_type" => "CNPJ"
                }
              }
            ]
          },
          overrides
        )

      %{
        "type" => "order_details",
        "body" => %{"text" => "Seu pedido"},
        "action" => %{"name" => "review_and_pay", "parameters" => params}
      }
    end

    test "order_details: valid pix order" do
      assert {:ok, _} = Validation.validate_send(msg("interactive", order()))
    end

    test "order_details: subtotal must equal the items sum" do
      bad = put_in(order(), ["action", "parameters", "order", "subtotal", "value"], 4900)
      assert user_msg(Validation.validate_send(msg("interactive", bad))) =~ "subtotal"
    end

    test "order_details: total must equal subtotal + tax + shipping - discount" do
      assert user_msg(
               Validation.validate_send(
                 msg(
                   "interactive",
                   order(%{"total_amount" => %{"value" => 5000, "offset" => 100}})
                 )
               )
             ) =~ "total_amount"
    end

    test "order_details: sale_amount counts toward the subtotal" do
      o = order()

      o =
        put_in(o, ["action", "parameters", "order", "items", Access.at(1), "sale_amount"], %{
          "value" => 500,
          "offset" => 100
        })

      o = put_in(o, ["action", "parameters", "order", "subtotal", "value"], 4500)
      o = put_in(o, ["action", "parameters", "total_amount", "value"], 5000)
      assert {:ok, _} = Validation.validate_send(msg("interactive", o))
    end

    test "order_details: field rules" do
      assert user_msg(Validation.validate_send(msg("interactive", order(%{"currency" => "USD"})))) =~
               "currency"

      assert user_msg(
               Validation.validate_send(
                 msg("interactive", order(%{"reference_id" => "tem espaço"}))
               )
             ) =~ "reference_id"

      assert user_msg(
               Validation.validate_send(
                 msg(
                   "interactive",
                   order(%{"total_amount" => %{"value" => 5500, "offset" => 1000}})
                 )
               )
             ) =~ "offset"

      no_sku =
        update_in(
          order(),
          ["action", "parameters", "order", "items", Access.at(0)],
          &Map.delete(&1, "retailer_id")
        )

      assert user_msg(Validation.validate_send(msg("interactive", no_sku))) =~ "retailer_id"

      bad_key =
        put_in(
          order(),
          [
            "action",
            "parameters",
            "payment_settings",
            Access.at(0),
            "pix_dynamic_code",
            "key_type"
          ],
          "RG"
        )

      assert user_msg(Validation.validate_send(msg("interactive", bad_key))) =~ "key_type"
    end

    test "unknown interactive types are whelx gaps" do
      assert {:error, %Error{user_msg: "whelx: not supported" <> _}} =
               Validation.validate_send(
                 msg("interactive", %{"type" => "flow", "body" => %{"text" => "x"}})
               )
    end
  end

  describe "validate_template_definition/1" do
    defp tpl(overrides \\ %{}) do
      Map.merge(
        %{
          "name" => "crm_campaign_message",
          "language" => "pt_BR",
          "category" => "MARKETING",
          "components" => [
            %{
              "type" => "BODY",
              "text" => "Olá *{{1}}*: {{2}}",
              "example" => %{"body_text" => [["Ana", "promo"]]}
            }
          ]
        },
        overrides
      )
    end

    test "accepts a typical campaign template" do
      assert :ok = Validation.validate_template_definition(tpl())
    end

    test "name must be lowercase snake case" do
      assert user_msg(Validation.validate_template_definition(tpl(%{"name" => "Promo Legal"}))) =~
               "name"
    end

    test "category must be known" do
      assert user_msg(Validation.validate_template_definition(tpl(%{"category" => "SPAM"}))) =~
               "category"

      assert :ok = Validation.validate_template_definition(tpl(%{"category" => "utility"}))
    end

    test "exactly one BODY and examples for variables" do
      assert user_msg(
               Validation.validate_template_definition(
                 tpl(%{"components" => [%{"type" => "FOOTER", "text" => "x"}]})
               )
             ) =~ "BODY"

      no_example = tpl(%{"components" => [%{"type" => "BODY", "text" => "Olá {{1}}"}]})
      assert user_msg(Validation.validate_template_definition(no_example)) =~ "example"

      gap =
        tpl(%{
          "components" => [
            %{
              "type" => "BODY",
              "text" => "{{1}} {{3}}",
              "example" => %{"body_text" => [["a", "b"]]}
            }
          ]
        })

      assert user_msg(Validation.validate_template_definition(gap)) =~ "sequential"
    end

    test "media header requires header_handle and buttons are validated" do
      header = %{"type" => "HEADER", "format" => "IMAGE"}

      assert user_msg(
               Validation.validate_template_definition(
                 tpl(%{"components" => [header | tpl()["components"]]})
               )
             ) =~ "header_handle"

      ok_header = Map.put(header, "example", %{"header_handle" => ["4:abc"]})

      assert :ok =
               Validation.validate_template_definition(
                 tpl(%{"components" => [ok_header | tpl()["components"]]})
               )

      buttons = %{
        "type" => "BUTTONS",
        "buttons" => [
          %{"type" => "QUICK_REPLY", "text" => "Sim, quero participar"},
          %{"type" => "QUICK_REPLY", "text" => "Não fui eu"}
        ]
      }

      assert :ok =
               Validation.validate_template_definition(
                 tpl(%{"components" => tpl()["components"] ++ [buttons]})
               )

      bad = put_in(buttons, ["buttons", Access.at(0), "type"], "TELEPORT")

      assert user_msg(
               Validation.validate_template_definition(
                 tpl(%{"components" => tpl()["components"] ++ [bad]})
               )
             ) =~ "invalid button type"
    end
  end
end
