defmodule Whelx.Messaging.StatusWorker do
  @moduledoc "Applies one scheduled status transition."
  use Oban.Worker, queue: :statuses, max_attempts: 3

  alias Whelx.Messaging
  alias Whelx.Messaging.StatusLifecycle

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => id, "status" => status}}) do
    case Messaging.transition(id, status) do
      {:ok, message} -> StatusLifecycle.next(message, message.conversation.contact)
      {:skip, _reason} -> :ok
    end
  end
end
