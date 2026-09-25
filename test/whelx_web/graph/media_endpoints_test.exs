defmodule WhelxWeb.Graph.MediaEndpointsTest do
  use WhelxWeb.ConnCase
  import Whelx.Fixtures
  alias Whelx.{Media, Messaging, Templates, Webhooks}

  setup do
    File.rm_rf!(Whelx.data_dir())
    account_fixture()
  end

  test "GET /{media_id} returns metadata and the URL serves the binary with a token", %{
    conn: conn,
    token: token
  } do
    {:ok, media} = Media.store("OggS-binary", "audio/ogg; codecs=opus")

    body = conn |> graph_auth(token) |> get("/v25.0/#{media.id}") |> json_response(200)
    expected_sha = Base.encode64(:crypto.hash(:sha256, "OggS-binary"))

    assert body == %{
             "messaging_product" => "whatsapp",
             "url" => "http://whelx.test/_media/#{media.id}",
             "mime_type" => "audio/ogg; codecs=opus",
             "sha256" => expected_sha,
             "file_size" => 11,
             "id" => media.id
           }

    conn = build_conn() |> graph_auth(token) |> get("/_media/#{media.id}")
    assert response(conn, 200) == "OggS-binary"
    assert get_resp_header(conn, "content-type") == ["audio/ogg; codecs=opus"]

    assert %{"error" => %{"code" => 190}} =
             build_conn() |> get("/_media/#{media.id}") |> json_response(401)
  end

  test "resumable upload with a curl-based client's exact requests returns a header handle", %{
    conn: conn,
    app: app,
    token: token
  } do
    conn =
      post(
        conn,
        "/v25.0/#{app.id}/uploads?file_name=promo.jpg&file_length=6&file_type=image/jpeg&access_token=#{token}"
      )

    assert %{"id" => "upload:" <> _ = session_id} = json_response(conn, 200)

    conn =
      build_conn()
      |> put_req_header("authorization", "OAuth " <> token)
      |> put_req_header("file_offset", "0")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/v25.0/#{session_id}", <<255, 216, 255, 0, 1, 2>>)

    assert %{"h" => handle} = json_response(conn, 200)
    assert handle =~ ~r/^4:/
    assert Media.handle_exists?(handle)

    status =
      build_conn() |> graph_auth(token) |> get("/v25.0/#{session_id}") |> json_response(200)

    assert status == %{"id" => session_id, "file_offset" => 6}
  end

  test "resumable upload rejects a wrong file_offset", %{conn: conn, app: app, token: token} do
    %{"id" => session_id} =
      conn
      |> post(
        "/v25.0/#{app.id}/uploads?file_name=a.png&file_length=4&file_type=image/png&access_token=#{token}"
      )
      |> json_response(200)

    conn =
      build_conn()
      |> put_req_header("authorization", "OAuth " <> token)
      |> put_req_header("file_offset", "2")
      |> put_req_header("content-type", "application/octet-stream")
      |> post("/v25.0/#{session_id}", "AB")

    assert %{"error" => %{"code" => 100}} = json_response(conn, 400)
  end

  test "upload session requires file_length and file_type", %{conn: conn, app: app, token: token} do
    conn = post(conn, "/v25.0/#{app.id}/uploads?file_name=a.png&access_token=#{token}")
    assert %{"error" => %{"code" => 100}} = json_response(conn, 400)
  end

  test "media template headers must reference an uploaded handle", %{waba: waba, app: app} do
    header = %{
      "type" => "HEADER",
      "format" => "IMAGE",
      "example" => %{"header_handle" => ["4:unknown"]}
    }

    params =
      template_params(%{
        "name" => "promo_img",
        "components" => [header | template_params()["components"]]
      })

    assert {:error, %{code: 100, user_msg: msg}} = Templates.create_template(waba.id, params)
    assert msg =~ "header_handle"

    {:ok, session} =
      Media.create_upload_session(app.id, %{
        "file_name" => "a.png",
        "file_length" => "2",
        "file_type" => "image/png"
      })

    {:ok, session} = Media.append_upload(session.id, 0, "AB")

    params =
      put_in(params, ["components", Access.at(0), "example", "header_handle"], [session.handle])

    assert {:ok, _} = Templates.create_template(waba.id, params)
  end

  test "receive_inbound_media/6 stores the file and the webhook carries id, sha256, url and voice",
       %{phone: phone} do
    {:ok, msg} =
      Messaging.receive_inbound_media(
        phone.id,
        "5511977776666",
        "audio",
        "OggS",
        "audio/ogg; codecs=opus",
        []
      )

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

    audio = message["audio"]
    assert message["type"] == "audio"
    assert audio["mime_type"] == "audio/ogg; codecs=opus"
    assert audio["voice"] == true
    assert audio["sha256"] == Base.encode64(:crypto.hash(:sha256, "OggS"))
    assert audio["url"] == "http://whelx.test/_media/#{audio["id"]}"
    assert Media.get_media(audio["id"])
    assert msg.type == "audio"
  end

  test "image with caption and document with filename", %{phone: phone} do
    {:ok, img} =
      Messaging.receive_inbound_media(phone.id, "5511977776666", "image", "PNG", "image/png",
        caption: "cardápio"
      )

    assert %{"caption" => "cardápio", "mime_type" => "image/png"} =
             Whelx.Messaging.Message.content(img)

    {:ok, doc} =
      Messaging.receive_inbound_media(
        phone.id,
        "5511977776666",
        "document",
        "%PDF",
        "application/pdf",
        file_name: "nota.pdf"
      )

    assert %{"filename" => "nota.pdf"} = Whelx.Messaging.Message.content(doc)
  end
end
