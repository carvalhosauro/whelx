defmodule Whelx.Webhooks.Payload do
  @moduledoc "Builders for webhook payloads in the exact shape Meta sends."

  alias Whelx.Accounts.PhoneNumber
  alias Whelx.Attrs

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
end
