defmodule Whelx.Mcp.Tools do
  @moduledoc "MCP tool catalogue, mapped onto `Whelx.Control` and friends."

  alias Whelx.{Chaos, Contacts, Control, Messaging, Templates, Webhooks}
  alias Whelx.Control.{JSON, Waiter}

  @tools [
    {"seed",
     "Creates/updates the scenario (app, wabas with phone_numbers, tokens, contacts, templates, settings, chaos). Idempotent.",
     %{
       "app" => %{"type" => "object"},
       "wabas" => %{"type" => "array"},
       "tokens" => %{"type" => "array"},
       "contacts" => %{"type" => "array"},
       "templates" => %{"type" => "array"},
       "settings" => %{"type" => "object"},
       "chaos" => %{"type" => "object"}
     }, []},
    {"reset",
     "Deletes test data (messages, conversations, webhooks, logs). keep: list with contacts and/or templates.",
     %{
       "keep" => %{
         "type" => "array",
         "items" => %{"type" => "string", "enum" => ["contacts", "templates"]}
       }
     }, []},
    {"get_config",
     "Current configuration: app (secret, verify token, webhook_url), wabas, phone numbers, tokens, settings, chaos.",
     %{}, []},
    {"env_block", ".env block that points your application at whelx.", %{}, []},
    {"send_as_contact",
     "A fake contact sends a message to a business number. type: text|location|reaction|image|audio|video|document.",
     %{
       "wa_id" => %{"type" => "string"},
       "type" => %{"type" => "string"},
       "text" => %{"type" => "string"},
       "phone_number_id" => %{"type" => "string"},
       "context_wamid" => %{"type" => "string"},
       "message_id" => %{"type" => "string"},
       "emoji" => %{"type" => "string"},
       "latitude" => %{"type" => "number"},
       "longitude" => %{"type" => "number"},
       "name" => %{"type" => "string"},
       "address" => %{"type" => "string"},
       "media_base64" => %{"type" => "string"},
       "mime_type" => %{"type" => "string"},
       "caption" => %{"type" => "string"},
       "file_name" => %{"type" => "string"}
     }, ["wa_id", "type"]},
    {"reply_interactive",
     "The contact taps a button, list row or template quick reply on a business message.",
     %{
       "wa_id" => %{"type" => "string"},
       "wamid" => %{"type" => "string"},
       "id" => %{
         "type" => "string",
         "description" => "reply id, row id, quick reply index or payload"
       }
     }, ["wa_id", "wamid", "id"]},
    {"wait_for",
     "Waits (long-poll) until: kind=outbound_message (contact, after, type), status (wamid, status) or webhook_delivery (message_wamid, state).",
     %{
       "kind" => %{
         "type" => "string",
         "enum" => ["outbound_message", "status", "webhook_delivery"]
       },
       "contact" => %{"type" => "string"},
       "after" => %{"type" => "string"},
       "type" => %{"type" => "string"},
       "wamid" => %{"type" => "string"},
       "status" => %{"type" => "string"},
       "message_wamid" => %{"type" => "string"},
       "state" => %{"type" => "string"},
       "timeout_ms" => %{"type" => "integer"}
     }, ["kind"]},
    {"list_messages",
     "Lists messages (newest first). Filters: contact, direction, type, status, phone_number_id, limit.",
     %{
       "contact" => %{"type" => "string"},
       "direction" => %{"type" => "string"},
       "type" => %{"type" => "string"},
       "status" => %{"type" => "string"},
       "phone_number_id" => %{"type" => "string"},
       "limit" => %{"type" => "integer"}
     }, []},
    {"list_contacts", "Lists fake contacts.", %{}, []},
    {"set_contact",
     "Updates a contact: behavior (normal|invalid_number|blocked), online, read_policy (on_open|auto|never), read_after_ms, profile_name.",
     %{
       "wa_id" => %{"type" => "string"},
       "behavior" => %{"type" => "string"},
       "online" => %{"type" => "boolean"},
       "read_policy" => %{"type" => "string"},
       "read_after_ms" => %{"type" => "integer"},
       "profile_name" => %{"type" => "string"}
     }, ["wa_id"]},
    {"bulk_contacts", "Generates N fake contacts (for campaigns).",
     %{"count" => %{"type" => "integer"}}, ["count"]},
    {"list_templates", "Lists templates (all WABAs or waba_id).",
     %{"waba_id" => %{"type" => "string"}}, []},
    {"approve_template", "Approves a template.", %{"id" => %{"type" => "string"}}, ["id"]},
    {"reject_template", "Rejects a template with a reason.",
     %{"id" => %{"type" => "string"}, "reason" => %{"type" => "string"}}, ["id"]},
    {"set_chaos",
     "Updates chaos: preset (off|flaky|hostile) or fields (seed, latency_min_ms, latency_max_ms, *_rate, sync_error_codes, async_fail_codes, webhook_extra_delay_ms).",
     %{
       "preset" => %{"type" => "string"},
       "seed" => %{"type" => "integer"},
       "drop_rate" => %{"type" => "number"},
       "duplicate_rate" => %{"type" => "number"},
       "reorder_rate" => %{"type" => "number"},
       "batch_rate" => %{"type" => "number"},
       "sync_error_rate" => %{"type" => "number"},
       "async_fail_rate" => %{"type" => "number"},
       "latency_min_ms" => %{"type" => "integer"},
       "latency_max_ms" => %{"type" => "integer"}
     }, []},
    {"list_webhook_deliveries",
     "Webhook deliveries (payload, signature, HTTP status, attempts). Filters: message_wamid, state, limit.",
     %{
       "message_wamid" => %{"type" => "string"},
       "state" => %{"type" => "string"},
       "limit" => %{"type" => "integer"}
     }, []},
    {"redeliver_webhook", "Redelivers a webhook (tests idempotency).",
     %{"id" => %{"type" => "integer"}}, ["id"]},
    {"verify_webhook", "Runs the hub.challenge handshake against the webhook_url.", %{}, []},
    {"expire_window", "Forces a conversation's 24h window to expire.",
     %{"conversation_id" => %{"type" => "integer"}}, ["conversation_id"]}
  ]

  def list do
    for {name, description, props, required} <- @tools do
      %{
        "name" => name,
        "description" => description,
        "inputSchema" => %{"type" => "object", "properties" => props, "required" => required}
      }
    end
  end

  def known?(name), do: Enum.any?(@tools, &(elem(&1, 0) == name))

  @spec call(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def call("seed", args), do: Control.seed(args) |> normalize()

  def call("reset", args) do
    :ok = Control.reset(args["keep"] || [])
    {:ok, %{"ok" => true}}
  end

  def call("get_config", _args), do: {:ok, Control.snapshot()}
  def call("env_block", _args), do: {:ok, Control.env_block()}

  def call("send_as_contact", %{"wa_id" => wa_id} = args),
    do: Control.send_as_contact(wa_id, Map.delete(args, "wa_id")) |> message()

  def call("reply_interactive", %{"wa_id" => wa_id, "wamid" => wamid, "id" => id}),
    do: Control.reply_interactive(wa_id, wamid, id) |> message()

  def call("wait_for", args) do
    case Waiter.wait(args) do
      {:ok, found} -> {:ok, found}
      {:timeout, observed} -> {:error, "timeout: " <> Jason.encode!(observed)}
      {:error, reason} -> {:error, reason}
    end
  end

  def call("list_messages", args),
    do: {:ok, Enum.map(Messaging.list_messages(args), &JSON.message/1)}

  def call("list_contacts", _args), do: {:ok, Enum.map(Contacts.list_contacts(), &JSON.contact/1)}

  def call("set_contact", %{"wa_id" => wa_id} = args) do
    with %{} = contact <-
           Contacts.get_contact(wa_id) || {:error, "contact #{wa_id} does not exist"},
         {:ok, contact} <- Contacts.update_contact(contact, Map.drop(args, ["wa_id", "online"])),
         {:ok, contact} <-
           if(is_boolean(args["online"]),
             do: Messaging.set_contact_online(contact, args["online"]),
             else: {:ok, contact}
           ) do
      {:ok, JSON.contact(contact)}
    end
    |> normalize()
  end

  def call("bulk_contacts", %{"count" => count}),
    do:
      Contacts.bulk_create(count)
      |> normalize()
      |> then(fn
        {:ok, n} -> {:ok, %{"count" => n}}
        e -> e
      end)

  def call("list_templates", args),
    do: {:ok, Enum.map(Templates.list_all(args["waba_id"]), &JSON.template/1)}

  def call("approve_template", %{"id" => id}), do: with_template(id, &Templates.approve/1)

  def call("reject_template", %{"id" => id} = args),
    do: with_template(id, &Templates.reject(&1, args["reason"] || "INVALID_FORMAT"))

  def call("set_chaos", %{"preset" => preset} = args) when map_size(args) == 1 do
    case Chaos.apply_preset(preset) do
      {:ok, profile} -> {:ok, JSON.chaos(profile)}
      {:error, _} -> {:error, "unknown preset: #{preset}"}
    end
  end

  def call("set_chaos", args),
    do:
      Chaos.update_profile(args)
      |> normalize()
      |> then(fn
        {:ok, p} -> {:ok, JSON.chaos(p)}
        e -> e
      end)

  def call("list_webhook_deliveries", args),
    do:
      {:ok,
       Enum.map(
         Webhooks.list_deliveries(
           message_wamid: args["message_wamid"],
           state: args["state"],
           limit: args["limit"] || 50
         ),
         &JSON.delivery/1
       )}

  def call("redeliver_webhook", %{"id" => id}),
    do:
      Webhooks.redeliver(id)
      |> normalize()
      |> then(fn
        {:ok, d} -> {:ok, JSON.delivery(d)}
        e -> e
      end)

  def call("verify_webhook", _args), do: Webhooks.verify() |> normalize()

  def call("expire_window", %{"conversation_id" => id}) do
    conversation = Messaging.get_conversation!(id)
    {:ok, _} = Messaging.expire_window(conversation)
    {:ok, JSON.conversation(Messaging.get_conversation!(id))}
  rescue
    Ecto.NoResultsError -> {:error, "conversation #{id} does not exist"}
  end

  def call(name, _args), do: {:error, "invalid arguments for #{name}"}

  defp with_template(id, fun) do
    case Templates.get_template(id) do
      nil ->
        {:error, "template #{id} does not exist"}

      template ->
        fun.(template)
        |> normalize()
        |> then(fn
          {:ok, t} -> {:ok, JSON.template(t)}
          e -> e
        end)
    end
  end

  defp message({:ok, message}),
    do: {:ok, message.wamid |> Messaging.get_message_by_wamid() |> JSON.message()}

  defp message(other), do: normalize(other)

  defp normalize({:ok, _} = ok), do: ok

  defp normalize({:error, %Ecto.Changeset{} = cs}),
    do: {:error, Jason.encode!(Control.changeset_errors(cs))}

  defp normalize({:error, %Whelx.Graph.Error{} = e}), do: {:error, e.user_msg || e.message}
  defp normalize({:error, reason}) when is_binary(reason), do: {:error, reason}
  defp normalize({:error, reason}), do: {:error, inspect(reason)}
end
