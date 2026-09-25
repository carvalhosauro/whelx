defmodule Whelx.Control.Waiter do
  @moduledoc """
  Long-poll until a condition holds or the timeout expires. Lets E2E tests
  say "wait for the bot's reply" without sleeping.

  Kinds:
    * `outbound_message` — `contact` (required), `after` (wamid or ISO-8601), `type`
    * `status` — `wamid`, `status` (required)
    * `webhook_delivery` — `message_wamid` (required), `state` (default "delivered")
  """

  import Ecto.Query
  alias Whelx.{Attrs, Events, Messaging, Repo}
  alias Whelx.Control.JSON
  alias Whelx.Messaging.Message
  alias Whelx.Webhooks.Delivery

  @max_timeout 120_000
  @rank %{"accepted" => 0, "sent" => 1, "delivered" => 2, "read" => 3}

  @spec wait(map()) :: {:ok, map()} | {:timeout, map()} | {:error, String.t()}
  def wait(params) do
    params = Attrs.stringify(params)
    timeout = params["timeout_ms"] |> to_int(30_000) |> max(0) |> min(@max_timeout)

    with {:ok, condition} <- condition(params) do
      topic = topic(condition.kind)
      Events.subscribe(topic)
      deadline = System.monotonic_time(:millisecond) + timeout

      try do
        loop(condition, deadline)
      after
        Events.unsubscribe(topic)
      end
    end
  end

  defp loop(condition, deadline) do
    case check(condition) do
      {:ok, found} ->
        {:ok, found}

      :none ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {:timeout, observed(condition)}
        else
          receive do
            {event, _} when event in [:message_created, :message_updated, :delivery] ->
              loop(condition, deadline)
          after
            remaining -> final_check(condition)
          end
        end
    end
  end

  defp final_check(condition) do
    case check(condition) do
      {:ok, found} -> {:ok, found}
      :none -> {:timeout, observed(condition)}
    end
  end

  defp condition(%{"kind" => "outbound_message"} = p) do
    case Attrs.digits(p["contact"]) do
      "" ->
        {:error, "contact é obrigatório"}

      wa_id ->
        {:ok,
         %{
           kind: :outbound_message,
           contact: wa_id,
           type: p["type"],
           after_id: after_id(p["after"])
         }}
    end
  end

  defp condition(%{"kind" => "status", "wamid" => wamid, "status" => status})
       when is_binary(wamid) and status in ~w(sent delivered read failed),
       do: {:ok, %{kind: :status, wamid: wamid, status: status}}

  defp condition(%{"kind" => "status"}),
    do: {:error, "wamid e status (sent|delivered|read|failed) são obrigatórios"}

  defp condition(%{"kind" => "webhook_delivery", "message_wamid" => wamid} = p)
       when is_binary(wamid),
       do: {:ok, %{kind: :webhook_delivery, wamid: wamid, state: p["state"] || "delivered"}}

  defp condition(%{"kind" => "webhook_delivery"}), do: {:error, "message_wamid é obrigatório"}

  defp condition(p),
    do:
      {:error,
       "kind inválido: #{inspect(p["kind"])} (use outbound_message, status ou webhook_delivery)"}

  defp topic(:webhook_delivery), do: "deliveries"
  defp topic(_), do: "messages"

  defp after_id(nil), do: max_message_id()

  defp after_id("wamid." <> _ = wamid) do
    case Repo.one(from m in Message, where: m.wamid == ^wamid, select: m.id) do
      nil -> max_message_id()
      id -> id
    end
  end

  defp after_id(iso) do
    case DateTime.from_iso8601(to_string(iso)) do
      {:ok, at, _} ->
        Repo.one(from m in Message, where: m.inserted_at <= ^at, select: max(m.id)) || 0

      _ ->
        max_message_id()
    end
  end

  defp max_message_id, do: Repo.one(from m in Message, select: max(m.id)) || 0

  defp check(%{kind: :outbound_message} = c) do
    query =
      from m in Message,
        join: conv in assoc(m, :conversation),
        where:
          m.direction == "outbound" and conv.contact_wa_id == ^c.contact and m.id > ^c.after_id,
        order_by: [asc: m.id],
        limit: 1,
        preload: [conversation: conv]

    query = if c.type, do: where(query, [m], m.type == ^c.type), else: query

    case Repo.one(query) do
      nil -> :none
      message -> {:ok, JSON.message(message)}
    end
  end

  defp check(%{kind: :status} = c) do
    case Messaging.get_message_by_wamid(c.wamid) do
      %Message{} = m -> if reached?(m.status, c.status), do: {:ok, JSON.message(m)}, else: :none
      nil -> :none
    end
  end

  defp check(%{kind: :webhook_delivery} = c) do
    case Repo.one(
           from d in Delivery,
             where: d.message_wamid == ^c.wamid and d.state == ^c.state,
             order_by: [desc: d.id],
             limit: 1
         ) do
      nil -> :none
      delivery -> {:ok, JSON.delivery(delivery)}
    end
  end

  defp reached?("failed", "failed"), do: true
  defp reached?(_current, "failed"), do: false
  defp reached?("failed", _wanted), do: false
  defp reached?(current, wanted), do: Map.get(@rank, current, -1) >= Map.fetch!(@rank, wanted)

  defp observed(%{kind: :outbound_message} = c) do
    last =
      Repo.one(
        from m in Message,
          join: conv in assoc(m, :conversation),
          where: m.direction == "outbound" and conv.contact_wa_id == ^c.contact,
          order_by: [desc: m.id],
          limit: 1,
          preload: [conversation: conv]
      )

    %{"last_outbound" => last && JSON.message(last)}
  end

  defp observed(%{kind: :status} = c) do
    %{"message" => (m = Messaging.get_message_by_wamid(c.wamid)) && JSON.message(m)}
  end

  defp observed(%{kind: :webhook_delivery} = c) do
    states = Repo.all(from d in Delivery, where: d.message_wamid == ^c.wamid, select: d.state)
    %{"delivery_states" => states}
  end

  defp to_int(nil, default), do: default
  defp to_int(v, _default) when is_integer(v), do: v

  defp to_int(v, default) do
    case Integer.parse(to_string(v)) do
      {n, _} -> n
      :error -> default
    end
  end
end
