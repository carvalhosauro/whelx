defmodule WhelxWeb.PageController do
  use WhelxWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
