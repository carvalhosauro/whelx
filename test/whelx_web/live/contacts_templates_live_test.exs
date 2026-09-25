defmodule WhelxWeb.ContactsTemplatesLiveTest do
  use WhelxWeb.ConnCase
  import Phoenix.LiveViewTest
  import Whelx.Fixtures
  alias Whelx.{Accounts, Contacts, Templates}

  setup do
    account_fixture()
  end

  describe "contacts" do
    test "creates, bulk generates, edits and deletes", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/contacts")

      view
      |> form("#contact-form", contact: %{profile_name: "Bia", wa_id: "5511912345678"})
      |> render_submit()

      assert Contacts.get_contact("5511912345678")

      view |> form("#bulk-form", bulk: %{count: "5"}) |> render_submit()
      assert length(Contacts.list_contacts()) == 6

      view
      |> form("#contact-5511912345678", edit: %{behavior: "invalid_number", read_policy: "auto"})
      |> render_change()

      assert %{behavior: "invalid_number", read_policy: "auto"} =
               Contacts.get_contact("5511912345678")

      view
      |> element(~s(button[phx-click="toggle_online"][phx-value-id="5511912345678"]))
      |> render_click()

      refute Contacts.get_contact("5511912345678").online

      view
      |> element(~s(button[phx-click="delete"][phx-value-id="5511912345678"]))
      |> render_click()

      refute Contacts.get_contact("5511912345678")
    end

    test "invalid number shows an error", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/contacts")
      html = view |> form("#contact-form", contact: %{wa_id: "12"}) |> render_submit()
      assert html =~ "8 to 15 digits"
    end
  end

  describe "templates" do
    test "lists, approves, rejects and previews", %{conn: conn, waba: waba} do
      {:ok, t} = Templates.create_template(waba.id, template_params())
      {:ok, view, html} = live(conn, ~p"/templates")
      assert html =~ "crm_campaign_message"
      assert html =~ "PENDING"

      view |> element(~s(button[phx-click="approve"][phx-value-id="#{t.id}"])) |> render_click()
      assert Templates.get_template(t.id).status == "APPROVED"

      view |> element(~s(button[phx-click="reject"][phx-value-id="#{t.id}"])) |> render_click()
      assert %{status: "REJECTED"} = Templates.get_template(t.id)

      html =
        view |> element(~s(button[phx-click="preview"][phx-value-id="#{t.id}"])) |> render_click()

      assert html =~ "Enviado via Loja"
    end

    test "updates approval policy", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/templates")

      view
      |> form("#policy-form",
        policy: %{template_approval_policy: "auto_approve", template_review_after_ms: "1000"}
      )
      |> render_submit()

      assert %{template_approval_policy: "auto_approve", template_review_after_ms: 1000} =
               Accounts.get_settings()
    end

    test "new templates appear live", %{conn: conn, waba: waba} do
      {:ok, view, _} = live(conn, ~p"/templates")
      {:ok, _} = Templates.create_template(waba.id, template_params(%{"name" => "live_one"}))
      assert render(view) =~ "live_one"
    end
  end
end
