defmodule WhelxWeb.ErrorJSON do
  @moduledoc "JSON error rendering. 500s use the Meta error shape (code 1)."

  def render("500.json", _assigns), do: Whelx.Graph.Error.to_body(Whelx.Graph.Error.new(1))

  def render(template, _assigns),
    do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
end
