defmodule Whelx.Control.JSON do
  @moduledoc "JSON views shared by the REST control API and MCP tools."

  alias Whelx.Accounts.{AccessToken, App, PhoneNumber, Settings, Waba}
  alias Whelx.Chaos.Profile
  alias Whelx.Contacts.Contact
  alias Whelx.Logs.GraphRequest
  alias Whelx.Messaging.{Conversation, Message}
  alias Whelx.Templates.Template
  alias Whelx.Webhooks.Delivery

  def app(%App{} = a),
    do: %{
      "app_id" => a.id,
      "name" => a.name,
      "app_secret" => a.app_secret,
      "verify_token" => a.verify_token,
      "webhook_url" => a.webhook_url
    }

  def waba(%Waba{} = w, phones),
    do: %{
      "id" => w.id,
      "name" => w.name,
      "subscribed" => w.subscribed,
      "override_callback_uri" => w.override_callback_uri,
      "phone_numbers" => Enum.map(phones, &phone/1)
    }

  def phone(%PhoneNumber{} = p) do
    %{
      "id" => p.id,
      "waba_id" => p.waba_id,
      "display_phone_number" => p.display_phone_number,
      "verified_name" => p.verified_name,
      "quality_rating" => p.quality_rating,
      "throughput_mps" => p.throughput_mps,
      "override_callback_uri" => p.override_callback_uri
    }
  end

  def token(%AccessToken{} = t),
    do: %{"token" => t.token, "waba_ids" => t.waba_ids, "expires_at" => t.expires_at}

  def settings(%Settings{} = s) do
    Map.new(
      ~w(webhook_retry_profile template_approval_policy template_review_after_ms template_reject_reason sent_delay_ms delivered_delay_ms pair_rate_limit_enabled pair_rate_limit_burst pair_rate_limit_interval_ms)a,
      &{Atom.to_string(&1), Map.fetch!(s, &1)}
    )
  end

  def chaos(%Profile{} = p) do
    p
    |> Map.from_struct()
    |> Map.drop([:__meta__, :id, :inserted_at, :updated_at])
    |> Map.update(:phone_number_ids, [], &(&1 || []))
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  def contact(%Contact{} = c) do
    %{
      "wa_id" => c.wa_id,
      "profile_name" => c.profile_name,
      "behavior" => c.behavior,
      "online" => c.online,
      "read_policy" => c.read_policy,
      "read_after_ms" => c.read_after_ms
    }
  end

  def message(%Message{} = m) do
    conversation = if match?(%Conversation{}, m.conversation), do: m.conversation

    %{
      "id" => m.id,
      "wamid" => m.wamid,
      "direction" => m.direction,
      "type" => m.type,
      "status" => m.status,
      "content" => Message.content(m),
      "rendered" => m.payload["rendered"],
      "errors" => m.errors,
      "context_wamid" => m.context_wamid,
      "chaos_tag" => m.chaos_tag,
      "conversation_id" => m.conversation_id,
      "contact" => conversation && conversation.contact_wa_id,
      "phone_number_id" => conversation && conversation.phone_number_id,
      "inserted_at" => m.inserted_at,
      "sent_at" => m.sent_at,
      "delivered_at" => m.delivered_at,
      "read_at" => m.read_at,
      "failed_at" => m.failed_at
    }
  end

  def conversation(%Conversation{} = c) do
    base = %{
      "id" => c.id,
      "phone_number_id" => c.phone_number_id,
      "contact" => c.contact_wa_id,
      "window_expires_at" => c.window_expires_at,
      "window_open" => Whelx.Messaging.window_open?(c),
      "typing_until" => c.typing_until,
      "unread_count" => c.unread_count,
      "last_message_at" => c.last_message_at
    }

    case c.messages do
      messages when is_list(messages) ->
        Map.put(base, "messages", Enum.map(messages, &message(%{&1 | conversation: c})))

      _ ->
        base
    end
  end

  def template(%Template{} = t) do
    %{
      "id" => t.id,
      "waba_id" => t.waba_id,
      "name" => t.name,
      "language" => t.language,
      "category" => t.category,
      "status" => t.status,
      "rejected_reason" => t.rejected_reason,
      "components" => t.components
    }
  end

  def delivery(%Delivery{} = d) do
    %{
      "id" => d.id,
      "waba_id" => d.waba_id,
      "kind" => d.kind,
      "state" => d.state,
      "attempts" => d.attempts,
      "last_status" => d.last_status,
      "last_response_body" => d.last_response_body,
      "last_error" => d.last_error,
      "latency_ms" => d.latency_ms,
      "chaos_tag" => d.chaos_tag,
      "message_wamid" => d.message_wamid,
      "merged_into_id" => d.merged_into_id,
      "signature" => d.signature,
      "payload" => d.payload,
      "inserted_at" => d.inserted_at,
      "updated_at" => d.updated_at
    }
  end

  def request(%GraphRequest{} = r) do
    %{
      "id" => r.id,
      "method" => r.method,
      "path" => r.path,
      "query" => r.query,
      "request_headers" => r.request_headers,
      "request_body" => r.request_body,
      "response_status" => r.response_status,
      "response_body" => r.response_body,
      "duration_ms" => r.duration_ms,
      "chaos_tag" => r.chaos_tag,
      "internal_error" => r.internal_error,
      "inserted_at" => r.inserted_at
    }
  end
end
