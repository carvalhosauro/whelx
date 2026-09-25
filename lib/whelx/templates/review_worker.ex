defmodule Whelx.Templates.ReviewWorker do
  @moduledoc "Applies the automatic template review decision."
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Whelx.{Accounts, Templates}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"template_id" => id, "decision" => decision}}) do
    case Templates.get_template(id) do
      %{status: "PENDING"} = template -> apply_decision(template, decision)
      _ -> :ok
    end
  end

  defp apply_decision(template, "approve"), do: ok(Templates.approve(template))

  defp apply_decision(template, "reject"),
    do: ok(Templates.reject(template, Accounts.get_settings().template_reject_reason))

  defp ok({:ok, _}), do: :ok
  defp ok(error), do: error
end
