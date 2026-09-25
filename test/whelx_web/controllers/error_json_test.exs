defmodule WhelxWeb.ErrorJSONTest do
  use WhelxWeb.ConnCase, async: true

  test "renders 500 in the Meta error shape" do
    assert %{"error" => %{"code" => 1, "message" => "An unknown error occurred"}} =
             WhelxWeb.ErrorJSON.render("500.json", %{})
  end

  test "renders 404" do
    assert WhelxWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end
end
