defmodule Whelx.TemplatesTest do
  use Whelx.DataCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Templates}
  alias Whelx.Graph.Error
  alias Whelx.Templates.ReviewWorker

  setup do
    account_fixture()
  end

  test "create_template/2 starts PENDING with upcased category", %{waba: waba} do
    {:ok, t} = Templates.create_template(waba.id, template_params(%{"category" => "marketing"}))
    assert t.status == "PENDING"
    assert t.category == "MARKETING"
    assert t.id =~ ~r/^\d{15}$/
    assert [%{"type" => "BODY"}] = t.components
    refute_enqueued(worker: ReviewWorker)
  end

  test "duplicate name+language is rejected like Meta", %{waba: waba} do
    {:ok, _} = Templates.create_template(waba.id, template_params())

    assert {:error, %Error{code: 100, subcode: 2_388_024}} =
             Templates.create_template(waba.id, template_params())

    assert {:ok, _} =
             Templates.create_template(waba.id, template_params(%{"language" => "en_US"}))
  end

  test "invalid definitions return code 100", %{waba: waba} do
    assert {:error, %Error{code: 100}} =
             Templates.create_template(waba.id, template_params(%{"name" => "Bad Name"}))
  end

  test "auto_approve policy schedules a review", %{waba: waba} do
    {:ok, _} =
      Accounts.update_settings(%{
        template_approval_policy: "auto_approve",
        template_review_after_ms: 0
      })

    {:ok, t} = Templates.create_template(waba.id, template_params())
    assert_enqueued(worker: ReviewWorker, args: %{"template_id" => t.id, "decision" => "approve"})
    assert :ok = perform_job(ReviewWorker, %{"template_id" => t.id, "decision" => "approve"})
    assert Templates.get_template(t.id).status == "APPROVED"
  end

  test "auto_reject stores the configured reason", %{waba: waba} do
    {:ok, _} =
      Accounts.update_settings(%{
        template_approval_policy: "auto_reject",
        template_reject_reason: "PROMOTIONAL"
      })

    {:ok, t} = Templates.create_template(waba.id, template_params())
    :ok = perform_job(ReviewWorker, %{"template_id" => t.id, "decision" => "reject"})
    assert %{status: "REJECTED", rejected_reason: "PROMOTIONAL"} = Templates.get_template(t.id)
  end

  test "review of a deleted template is a no-op" do
    assert :ok = perform_job(ReviewWorker, %{"template_id" => "0", "decision" => "approve"})
  end

  test "find_approved/3 only returns APPROVED templates", %{waba: waba} do
    {:ok, t} = Templates.create_template(waba.id, template_params())

    assert {:error, %Error{code: 132_001, details: details}} =
             Templates.find_approved(waba.id, t.name, "pt_BR")

    assert details =~ "PENDING"
    {:ok, _} = Templates.approve(t)
    assert {:ok, %{id: id}} = Templates.find_approved(waba.id, t.name, "pt_BR")
    assert id == t.id
    assert {:error, %Error{code: 132_001}} = Templates.find_approved(waba.id, t.name, "en_US")
  end

  test "check_params/2 compares body parameter count", %{waba: waba} do
    t = approved_template_fixture(waba.id)

    ok = [
      %{
        "type" => "body",
        "parameters" => [%{"type" => "text", "text" => "A"}, %{"type" => "text", "text" => "B"}]
      }
    ]

    assert :ok = Templates.check_params(t, ok)

    assert {:error, %Error{code: 132_000}} =
             Templates.check_params(t, [
               %{"type" => "body", "parameters" => [%{"type" => "text", "text" => "A"}]}
             ])

    assert {:error, %Error{code: 132_000}} = Templates.check_params(t, [])
  end

  test "render/2 fills variables and attaches quick reply payloads", %{waba: waba} do
    t =
      approved_template_fixture(waba.id, %{
        "name" => "reward_join",
        "category" => "UTILITY",
        "components" => [
          %{
            "type" => "HEADER",
            "format" => "TEXT",
            "text" => "Oi {{1}}",
            "example" => %{"header_text" => ["Ana"]}
          },
          %{
            "type" => "BODY",
            "text" => "Participar de {{1}}?",
            "example" => %{"body_text" => [["Fidelidade"]]}
          },
          %{"type" => "FOOTER", "text" => "Pigz"},
          %{
            "type" => "BUTTONS",
            "buttons" => [
              %{"type" => "QUICK_REPLY", "text" => "Sim"},
              %{"type" => "QUICK_REPLY", "text" => "Não"}
            ]
          }
        ]
      })

    rendered =
      Templates.render(t, [
        %{"type" => "header", "parameters" => [%{"type" => "text", "text" => "Bia"}]},
        %{"type" => "body", "parameters" => [%{"type" => "text", "text" => "Clube"}]},
        %{
          "type" => "button",
          "sub_type" => "quick_reply",
          "index" => "0",
          "parameters" => [%{"type" => "payload", "payload" => "reward_join:yes:tok"}]
        },
        %{
          "type" => "button",
          "sub_type" => "quick_reply",
          "index" => "1",
          "parameters" => [%{"type" => "payload", "payload" => "reward_join:no:tok"}]
        }
      ])

    assert rendered["header"] == %{"format" => "TEXT", "text" => "Oi Bia"}
    assert rendered["body"] == "Participar de Clube?"
    assert rendered["footer"] == "Pigz"

    assert [
             %{
               "index" => "0",
               "type" => "QUICK_REPLY",
               "text" => "Sim",
               "payload" => "reward_join:yes:tok"
             },
             %{"index" => "1", "payload" => "reward_join:no:tok"}
           ] =
             rendered["buttons"]
  end

  test "list_templates/2 paginates with cursors and filters", %{waba: waba} do
    for i <- 1..30,
        do:
          approved_template_fixture(waba.id, %{
            "name" => "t_#{String.pad_leading("#{i}", 2, "0")}"
          })

    {:ok, pending} =
      Templates.create_template(waba.id, template_params(%{"name" => "zz_pending"}))

    page1 = Templates.list_templates(waba.id, %{"limit" => 25})
    assert length(page1.data) == 25
    assert page1.after
    page2 = Templates.list_templates(waba.id, %{"limit" => 25, "after" => page1.after})
    assert length(page2.data) == 6
    assert page2.after == nil
    assert MapSet.disjoint?(MapSet.new(page1.data, & &1.id), MapSet.new(page2.data, & &1.id))

    assert [%{id: id}] = Templates.list_templates(waba.id, %{"status" => "pending"}).data
    assert id == pending.id
    assert length(Templates.list_templates(waba.id, %{"name" => "t_0"}).data) == 9
  end

  test "delete_by_name/2 removes all languages", %{waba: waba} do
    approved_template_fixture(waba.id)
    approved_template_fixture(waba.id, %{"language" => "en_US"})
    assert {:ok, 2} = Templates.delete_by_name(waba.id, "crm_campaign_message")
    assert {:error, %Error{code: 100}} = Templates.delete_by_name(waba.id, "crm_campaign_message")
  end
end
