defmodule Whelx.Webhooks.Payload do
  @moduledoc "Builders for webhook payloads in the exact shape Meta sends."

  alias Whelx.Accounts.PhoneNumber
  alias Whelx.Attrs
  alias Whelx.Contacts.Contact
  alias Whelx.Messaging.Message

  @spec envelope(String.t(), String.t(), map()) :: map()
  def envelope(waba_id, field, value) do
    %{
      "object" => "whatsapp_business_account",
      "entry" => [%{"id" => waba_id, "changes" => [%{"value" => value, "field" => field}]}]
    }
  end

  @spec metadata(PhoneNumber.t()) :: map()
  def metadata(%PhoneNumber{} = phone) do
    %{
      "display_phone_number" => Attrs.digits(phone.display_phone_number),
      "phone_number_id" => phone.id
    }
  end

  @doc "`messages` webhook for a message a contact sent."
  @spec inbound(Message.t(), PhoneNumber.t(), Contact.t()) :: map()
  def inbound(%Message{} = message, %PhoneNumber{} = phone, %Contact{} = contact) do
    value = %{
      "messaging_product" => "whatsapp",
      "metadata" => metadata(phone),
      "contacts" => [%{"profile" => %{"name" => contact.profile_name}, "wa_id" => contact.wa_id}],
      "messages" => [message_object(message, phone, contact)]
    }

    envelope(phone.waba_id, "messages", value)
  end

  defp message_object(message, phone, contact) do
    object = %{
      "from" => contact.wa_id,
      "id" => message.wamid,
      "timestamp" => Attrs.unix(message.inserted_at),
      "type" => message.type,
      message.type => Message.content(message)
    }

    case message.context_wamid do
      nil ->
        object

      wamid ->
        Map.put(object, "context", %{
          "from" => Attrs.digits(phone.display_phone_number),
          "id" => wamid
        })
    end
  end

  @doc "`statuses` webhook for an outbound message (v24+ shape: no `conversation`)."
  @spec status(Message.t(), PhoneNumber.t(), Contact.t()) :: map()
  def status(%Message{} = message, %PhoneNumber{} = phone, %Contact{} = contact) do
    status =
      %{
        "id" => message.wamid,
        "status" => message.status,
        "timestamp" => Attrs.unix(status_time(message)),
        "recipient_id" => contact.wa_id
      }
      |> put_status_extras(message)

    value = %{
      "messaging_product" => "whatsapp",
      "metadata" => metadata(phone),
      "statuses" => [status]
    }

    envelope(phone.waba_id, "messages", value)
  end

  defp put_status_extras(status, %Message{status: "failed", errors: errors}),
    do: Map.put(status, "errors", errors)

  defp put_status_extras(status, %Message{payload: %{"pricing" => pricing}}) when is_map(pricing),
    do: Map.put(status, "pricing", pricing)

  defp put_status_extras(status, _message), do: status

  defp status_time(%Message{status: "sent", sent_at: %DateTime{} = t}), do: t
  defp status_time(%Message{status: "delivered", delivered_at: %DateTime{} = t}), do: t
  defp status_time(%Message{status: "read", read_at: %DateTime{} = t}), do: t
  defp status_time(%Message{status: "failed", failed_at: %DateTime{} = t}), do: t
  defp status_time(%Message{updated_at: t}), do: t
end
