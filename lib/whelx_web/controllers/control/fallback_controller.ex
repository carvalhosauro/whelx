defmodule WhelxWeb.Control.FallbackController do
  use WhelxWeb, :controller

  def call(conn, {:error, :not_found}),
    do: conn |> put_status(404) |> json(%{"error" => "not_found"})

  def call(conn, {:error, %Ecto.Changeset{} = cs}),
    do:
      conn
      |> put_status(422)
      |> json(%{"error" => "validation", "details" => Whelx.Control.changeset_errors(cs)})

  def call(conn, {:error, %Whelx.Graph.Error{} = error}),
    do: conn |> put_status(422) |> json(Whelx.Graph.Error.to_body(error))

  def call(conn, {:error, reason}),
    do: conn |> put_status(422) |> json(%{"error" => format(reason)})

  defp format(reason) when is_binary(reason), do: reason
  defp format(reason) when is_map(reason), do: reason
  defp format(reason), do: inspect(reason)
end
