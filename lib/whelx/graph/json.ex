defmodule Whelx.Graph.JSON do
  @moduledoc "Graph API representations of account objects."
  alias Whelx.Accounts.{PhoneNumber, Waba}

  def waba(%Waba{} = w) do
    %{
      "id" => w.id,
      "name" => w.name,
      "currency" => "BRL",
      "timezone_id" => "25",
      "message_template_namespace" => "whelx_" <> w.id
    }
  end

  def phone_number(%PhoneNumber{} = p) do
    %{
      "id" => p.id,
      "display_phone_number" => p.display_phone_number,
      "verified_name" => p.verified_name,
      "quality_rating" => p.quality_rating,
      "code_verification_status" => "VERIFIED",
      "platform_type" => "CLOUD_API",
      "throughput" => %{"level" => "STANDARD"}
    }
  end
end
