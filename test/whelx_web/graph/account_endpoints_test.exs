defmodule WhelxWeb.Graph.AccountEndpointsTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures
  alias Whelx.{Accounts, Logs}

  setup do
    account_fixture()
  end

  test "GET /{waba}?fields=id returns only the id", %{conn: conn, waba: waba, token: token} do
    conn = conn |> graph_auth(token) |> get("/v25.0/#{waba.id}?fields=id")
    assert json_response(conn, 200) == %{"id" => waba.id}
  end

  test "any Graph version prefix is accepted", %{conn: conn, waba: waba, token: token} do
    conn = conn |> graph_auth(token) |> get("/v13.0/#{waba.id}")
    assert %{"id" => _, "name" => "Loja Teste"} = json_response(conn, 200)
  end

  test "an invalid version segment returns unknown path components", %{
    conn: conn,
    waba: waba,
    token: token
  } do
    conn = conn |> graph_auth(token) |> get("/latest/#{waba.id}")
    assert %{"error" => %{"code" => 2500}} = json_response(conn, 400)
  end

  test "a missing token returns OAuthException 190", %{conn: conn, waba: waba} do
    conn = get(conn, "/v25.0/#{waba.id}")
    body = json_response(conn, 401)
    assert %{"code" => 190, "type" => "OAuthException", "fbtrace_id" => trace} = body["error"]
    assert is_binary(trace)
  end

  test "the OAuth authorization scheme is accepted", %{conn: conn, waba: waba, token: token} do
    conn = conn |> put_req_header("authorization", "OAuth " <> token) |> get("/v25.0/#{waba.id}")
    assert json_response(conn, 200)["id"] == waba.id
  end

  test "a token without access to the waba returns permissions error 200", %{
    conn: conn,
    waba: waba
  } do
    {:ok, other} = Accounts.upsert_waba(%{name: "Outra"})
    {:ok, token} = Accounts.create_token([other.id])
    conn = conn |> graph_auth(token.token) |> get("/v25.0/#{waba.id}")
    assert %{"error" => %{"code" => 200}} = json_response(conn, 403)
  end

  test "an unknown object id returns code 100 subcode 33, not a 500", %{conn: conn, token: token} do
    conn = conn |> graph_auth(token) |> post("/v25.0/999999999999999/messages", %{})
    assert %{"error" => %{"code" => 100, "error_subcode" => 33}} = json_response(conn, 400)

    conn = build_conn() |> graph_auth(token) |> get("/v25.0/999999999999999")
    assert %{"error" => %{"code" => 100, "error_subcode" => 33}} = json_response(conn, 400)
  end

  test "phone_numbers accepts access_token in the query and honours fields",
       %{conn: conn, waba: waba, phone: phone, token: token} do
    conn =
      get(
        conn,
        "/v25.0/#{waba.id}/phone_numbers?fields=id,display_phone_number&access_token=#{token}"
      )

    assert %{"data" => [row]} = json_response(conn, 200)
    assert row == %{"id" => phone.id, "display_phone_number" => "+55 11 4000-0001"}
  end

  test "subscribed_apps POST and DELETE toggle the subscription", %{
    conn: conn,
    waba: waba,
    token: token
  } do
    {:ok, _} = Accounts.set_subscribed(waba.id, false)

    conn = conn |> graph_auth(token) |> post("/v25.0/#{waba.id}/subscribed_apps")
    assert json_response(conn, 200) == %{"success" => true}
    assert Accounts.get_waba(waba.id).subscribed

    conn = build_conn() |> graph_auth(token) |> delete("/v25.0/#{waba.id}/subscribed_apps")
    assert json_response(conn, 200) == %{"success" => true}
    refute Accounts.get_waba(waba.id).subscribed
  end

  test "requests are logged with the token masked", %{conn: conn, waba: waba, token: token} do
    conn |> graph_auth(token) |> get("/v25.0/#{waba.id}?fields=id&access_token=#{token}")
    assert [log] = Logs.list_requests()
    assert log.method == "GET"
    assert log.path == "/v25.0/#{waba.id}"
    assert log.response_status == 200
    refute log.request_headers["authorization"] =~ token
    refute log.query =~ token
    assert log.response_body =~ waba.id
  end
end
