defmodule Whelx.Webhooks.DeliveryWorker do
  @moduledoc "Delivers one webhook, retrying with the configured backoff profile."
  use Oban.Worker, queue: :webhooks, max_attempts: 9

  alias Whelx.{Accounts, Webhooks}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => id}, attempt: attempt}) do
    case Webhooks.get_delivery(id) do
      nil -> {:cancel, :not_found}
      %{state: state} when state in ~w(delivered merged dropped skipped failed) -> :ok
      delivery -> Webhooks.attempt(delivery, attempt)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    Webhooks.backoff_seconds(Accounts.get_settings().webhook_retry_profile, attempt)
  end
end
