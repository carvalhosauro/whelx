defmodule Whelx.Graph.Error do
  @moduledoc """
  Meta Graph API errors: synchronous error bodies and the error objects
  carried by `failed` status webhooks.
  """

  alias Whelx.Ids

  @enforce_keys [:code, :message, :status]
  defstruct [
    :code,
    :message,
    :status,
    :subcode,
    :user_title,
    :user_msg,
    :details,
    type: "OAuthException"
  ]

  @type t :: %__MODULE__{
          code: integer(),
          message: String.t(),
          status: pos_integer(),
          subcode: integer() | nil,
          user_title: String.t() | nil,
          user_msg: String.t() | nil,
          details: String.t() | nil,
          type: String.t()
        }

  @defaults %{
    1 => {500, "An unknown error occurred"},
    2 => {503, "Service temporarily unavailable"},
    100 => {400, "(#100) Invalid parameter"},
    190 => {401, "Invalid OAuth access token - Cannot parse access token"},
    200 => {403, "(#200) Permissions error"},
    2500 => {400, "Unknown path components"},
    130_429 => {400, "(#130429) Rate limit hit"},
    131_000 => {500, "(#131000) Something went wrong"},
    132_000 =>
      {400, "(#132000) Number of parameters does not match the expected number of params"},
    132_001 => {404, "(#132001) Template name does not exist in the translation"}
  }

  @async %{
    131_000 => {"Something went wrong", "Message failed to send due to an unknown error."},
    131_026 =>
      {"Message undeliverable",
       "Unable to deliver message. Reasons can include: the recipient phone number is not a WhatsApp phone number; the recipient has not accepted our new Terms of Service; the recipient is using an old WhatsApp version."},
    131_047 =>
      {"Re-engagement message",
       "Message failed to send because more than 24 hours have passed since the customer last replied to this number."},
    131_049 =>
      {"This message was not delivered to maintain healthy ecosystem engagement.",
       "In order to maintain a healthy ecosystem engagement, the message failed to be delivered."}
  }

  @spec new(integer(), keyword()) :: t()
  def new(code, opts \\ []) do
    {status, message} = Map.get(@defaults, code, {400, "(##{code}) Error"})

    %__MODULE__{
      code: code,
      status: Keyword.get(opts, :status, status),
      message: Keyword.get(opts, :message, message),
      subcode: opts[:subcode],
      user_title: opts[:user_title],
      user_msg: opts[:user_msg],
      details: opts[:details]
    }
  end

  @spec invalid_parameter(String.t(), keyword()) :: t()
  def invalid_parameter(user_msg, opts \\ []) do
    new(100, Keyword.merge([user_title: "Invalid parameter", user_msg: user_msg], opts))
  end

  @spec unknown_object(String.t(), String.t()) :: t()
  def unknown_object(method, id) do
    new(100,
      subcode: 33,
      message:
        "Unsupported #{method} request. Object with ID '#{id}' does not exist, cannot be loaded due to missing permissions, or does not support this operation."
    )
  end

  @spec unsupported(String.t()) :: t()
  def unsupported(what) do
    invalid_parameter("whelx: não suportado (#{what})",
      message: "(#100) whelx: não suportado: #{what}"
    )
  end

  @spec to_body(t()) :: map()
  def to_body(%__MODULE__{} = e) do
    error =
      %{
        "message" => e.message,
        "type" => e.type,
        "code" => e.code,
        "fbtrace_id" => Ids.fbtrace_id()
      }
      |> put_present("error_subcode", e.subcode)
      |> put_present("error_user_title", e.user_title)
      |> put_present("error_user_msg", e.user_msg)
      |> put_present("error_data", error_data(e.details))

    %{"error" => error}
  end

  @doc "Error object for `statuses[].errors[]` in a `failed` status webhook."
  @spec async(integer(), keyword()) :: map()
  def async(code, opts \\ []) do
    {title, details} =
      Map.get(@async, code, {"Error #{code}", "Message failed with code #{code}."})

    %{
      "code" => code,
      "title" => title,
      "message" => title,
      "error_data" => %{"details" => Keyword.get(opts, :details, details)}
    }
  end

  defp error_data(nil), do: nil
  defp error_data(details), do: %{"messaging_product" => "whatsapp", "details" => details}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
