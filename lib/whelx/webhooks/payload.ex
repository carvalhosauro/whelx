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
end
