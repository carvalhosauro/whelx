defmodule WhelxWeb.Graph.TemplateEndpointsTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures

  setup do
    account_fixture()
  end

  test "POST creates a template and answers like Meta", %{conn: conn, waba: waba, token: token} do
    conn =
      conn |> graph_auth(token) |> post("/v25.0/#{waba.id}/message_templates", template_params())

    assert %{"id" => id, "status" => "PENDING", "category" => "MARKETING"} =
             json_response(conn, 200)

    assert id =~ ~r/^\d+$/
  end

  test "POST duplicate returns 100/2388024", %{conn: conn, waba: waba, token: token} do
    conn |> graph_auth(token) |> post("/v25.0/#{waba.id}/message_templates", template_params())

    conn =
      build_conn()
      |> graph_auth(token)
      |> post("/v25.0/#{waba.id}/message_templates", template_params())

    assert %{"error" => %{"code" => 100, "error_subcode" => 2_388_024, "error_user_msg" => _}} =
             json_response(conn, 400)
  end

  test "GET lists with fields and paging like clients read it", %{
    conn: conn,
    waba: waba,
    token: token
  } do
    for i <- 1..3, do: approved_template_fixture(waba.id, %{"name" => "t#{i}"})

    conn =
      conn
      |> graph_auth(token)
      |> get(
        "/v25.0/#{waba.id}/message_templates?fields=name,status,category,language,components&limit=2"
      )

    body = json_response(conn, 200)

    assert [
             %{
               "id" => _,
               "name" => "t1",
               "status" => "APPROVED",
               "category" => "MARKETING",
               "language" => "pt_BR",
               "components" => [_]
             },
             _
           ] = body["data"]

    assert %{"cursors" => %{"before" => _, "after" => after_cursor}, "next" => next} =
             body["paging"]

    assert next =~ "http://whelx.test/v25.0/#{waba.id}/message_templates?"
    assert next =~ "after=#{after_cursor}"

    conn =
      build_conn()
      |> graph_auth(token)
      |> get("/v25.0/#{waba.id}/message_templates?limit=2&after=#{after_cursor}")

    body = json_response(conn, 200)
    assert [%{"name" => "t3"}] = body["data"]
    refute Map.has_key?(body["paging"], "next")
  end

  test "DELETE ?name= removes the template", %{conn: conn, waba: waba, token: token} do
    approved_template_fixture(waba.id)

    conn =
      conn
      |> graph_auth(token)
      |> delete("/v25.0/#{waba.id}/message_templates?name=crm_campaign_message")

    assert json_response(conn, 200) == %{"success" => true}
  end

  test "templates of a waba the token cannot access are forbidden", %{conn: conn, token: token} do
    {:ok, other} = Whelx.Accounts.upsert_waba(%{name: "Outra"})
    conn = conn |> graph_auth(token) |> get("/v25.0/#{other.id}/message_templates")
    assert %{"error" => %{"code" => 200}} = json_response(conn, 403)
  end
end
