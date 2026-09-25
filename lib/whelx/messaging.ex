defmodule Whelx.Messaging do
  @moduledoc "Conversations and messages between business numbers and fake contacts."

  import Ecto.Query
  alias Whelx.{Accounts, Contacts, Events, Ids, Repo, Webhooks}
  alias Whelx.Messaging.{Conversation, Message}
  alias Whelx.Webhooks.Payload

  @window_hours 24

  # Conversations

  @spec get_or_create_conversation(String.t(), String.t()) :: Conversation.t()
  def get_or_create_conversation(phone_number_id, wa_id) do
    case Repo.get_by(Conversation, phone_number_id: phone_number_id, contact_wa_id: wa_id) do
      nil ->
        %Conversation{phone_number_id: phone_number_id, contact_wa_id: wa_id}
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target: [:phone_number_id, :contact_wa_id]
        )
        |> case do
          %Conversation{id: nil} ->
            Repo.get_by!(Conversation, phone_number_id: phone_number_id, contact_wa_id: wa_id)

          conversation ->
            conversation
        end

      conversation ->
        conversation
    end
  end

  def get_conversation!(id) do
    Conversation |> Repo.get!(id) |> Repo.preload([:contact, :messages])
  end

  def list_conversations(phone_number_id) do
    Repo.all(
      from c in Conversation,
        where: c.phone_number_id == ^phone_number_id,
        order_by: [desc_nulls_last: c.last_message_at, desc: c.id],
        preload: [:contact]
    )
  end

  @doc "Last message of each conversation, keyed by conversation id."
  def last_messages([]), do: %{}

  def last_messages(conversation_ids) do
    last_ids =
      from m in Message,
        where: m.conversation_id in ^conversation_ids,
        group_by: m.conversation_id,
        select: max(m.id)

    Repo.all(from m in Message, where: m.id in subquery(last_ids))
    |> Map.new(&{&1.conversation_id, &1})
  end

  @spec window_open?(Conversation.t(), DateTime.t()) :: boolean()
  def window_open?(conversation, now \\ DateTime.utc_now())
  def window_open?(%Conversation{window_expires_at: nil}, _now), do: false
  def window_open?(%Conversation{window_expires_at: at}, now), do: DateTime.after?(at, now)

  def expire_window(%Conversation{} = conversation) do
    conversation
    |> Ecto.Changeset.change(window_expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update()
    |> tap(fn _ -> broadcast_conversation(conversation.id) end)
  end

  # Inbound

  @doc """
  A contact sends a message to a business number. Renews the 24h window and
  queues the `messages` webhook.
  """
  def receive_inbound(phone_number_id, wa_id, %{type: type, content: content} = attrs) do
    phone = Accounts.get_phone_number!(phone_number_id)
    contact = Contacts.find_or_create_contact(wa_id)
    conversation = get_or_create_conversation(phone.id, contact.wa_id)
    now = DateTime.utc_now()

    {:ok, message} =
      Repo.transaction(fn ->
        message =
          Repo.insert!(%Message{
            wamid: Ids.wamid(),
            conversation_id: conversation.id,
            direction: "inbound",
            type: type,
            payload: %{"content" => content},
            status: "received",
            context_wamid: attrs[:context_wamid]
          })

        conversation
        |> Ecto.Changeset.change(
          window_expires_at: DateTime.add(now, @window_hours, :hour),
          last_message_at: now
        )
        |> Repo.update!()

        message
      end)

    {:ok, _} =
      Webhooks.enqueue(phone.waba_id, "messages", Payload.inbound(message, phone, contact),
        message_wamid: message.wamid
      )

    broadcast_message(:message_created, message)
    broadcast_conversation(conversation.id)
    {:ok, message}
  end

  # Queries

  def get_message_by_wamid(wamid) do
    Message |> Repo.get_by(wamid: wamid) |> Repo.preload(conversation: :contact)
  end

  def list_messages(filters \\ %{}) do
    filters = Whelx.Attrs.stringify(filters)
    limit = parse_int(filters["limit"], 100)

    from(m in Message,
      join: c in assoc(m, :conversation),
      order_by: [desc: m.id],
      limit: ^limit,
      preload: [conversation: c]
    )
    |> filter_contact(filters["contact"])
    |> filter_eq(:direction, filters["direction"])
    |> filter_eq(:type, filters["type"])
    |> filter_eq(:status, filters["status"])
    |> filter_phone(filters["phone_number_id"])
    |> filter_after(filters["after_id"])
    |> Repo.all()
  end

  defp filter_contact(query, nil), do: query

  defp filter_contact(query, wa_id),
    do: where(query, [_m, c], c.contact_wa_id == ^Whelx.Attrs.digits(wa_id))

  defp filter_phone(query, nil), do: query
  defp filter_phone(query, id), do: where(query, [_m, c], c.phone_number_id == ^to_string(id))

  defp filter_eq(query, _field, nil), do: query
  defp filter_eq(query, field, value), do: where(query, [m], field(m, ^field) == ^value)

  defp filter_after(query, nil), do: query
  defp filter_after(query, id), do: where(query, [m], m.id > ^parse_int(id, 0))

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> default
    end
  end

  # Events

  @doc false
  def broadcast_message(event, %Message{} = message),
    do: Events.broadcast("messages", {event, message})

  @doc false
  def broadcast_conversation(id),
    do: Events.broadcast("conversations", {:conversation_updated, id})
end
