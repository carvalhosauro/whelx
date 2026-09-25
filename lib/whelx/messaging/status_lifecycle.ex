defmodule Whelx.Messaging.StatusLifecycle do
  @moduledoc """
  Schedules status progression of outbound messages:
  accepted → sent → delivered (contact online) → read (read policy),
  or accepted → failed for planned failures.
  """

  alias Whelx.Accounts
  alias Whelx.Messaging.{Message, StatusWorker}

  @spec start(Message.t()) :: :ok
  def start(%Message{} = message) do
    target = if message.planned_failure, do: "failed", else: "sent"
    schedule(message, target, Accounts.get_settings().sent_delay_ms)
  end

  @doc "Schedules the next step after `message` reached its current status."
  @spec next(Message.t(), Whelx.Contacts.Contact.t()) :: :ok
  def next(%Message{status: "sent"} = message, %{online: true}),
    do: schedule(message, "delivered", Accounts.get_settings().delivered_delay_ms)

  def next(%Message{status: "delivered"} = message, %{read_policy: "auto", read_after_ms: ms}),
    do: schedule(message, "read", ms)

  def next(_message, _contact), do: :ok

  @spec schedule(Message.t(), String.t(), non_neg_integer()) :: :ok
  def schedule(%Message{id: id}, status, delay_ms) do
    opts =
      if delay_ms > 0,
        do: [scheduled_at: DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)],
        else: []

    %{"message_id" => id, "status" => status} |> StatusWorker.new(opts) |> Oban.insert!()
    :ok
  end
end
