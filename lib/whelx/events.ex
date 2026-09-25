defmodule Whelx.Events do
  @moduledoc """
  PubSub facade. Topics: "config", "messages", "conversations",
  "deliveries", "requests", "templates".
  """

  @pubsub Whelx.PubSub

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic)

  @spec broadcast(String.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic, event), do: Phoenix.PubSub.broadcast(@pubsub, topic, event)
end
