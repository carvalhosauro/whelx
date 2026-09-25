defmodule Whelx.Contacts do
  @moduledoc "Fake WhatsApp users that talk to the business numbers."

  import Ecto.Query
  alias Whelx.{Attrs, Events, Ids, Repo}
  alias Whelx.Contacts.{Contact, Names}

  def list_contacts,
    do: Repo.all(from c in Contact, order_by: [asc: c.profile_name, asc: c.wa_id])

  def get_contact(wa_id), do: Repo.get(Contact, Attrs.digits(wa_id))

  def create_contact(attrs) do
    %Contact{} |> Contact.changeset(Attrs.stringify(attrs)) |> Repo.insert() |> notify()
  end

  def update_contact(%Contact{} = contact, attrs) do
    contact |> Contact.changeset(Attrs.stringify(attrs)) |> Repo.update() |> notify()
  end

  def delete_contact(%Contact{} = contact), do: contact |> Repo.delete() |> notify()

  @doc "Returns the contact for the number, creating a `normal` one if needed."
  @spec find_or_create_contact(String.t()) :: Contact.t()
  def find_or_create_contact(wa_id) do
    digits = Attrs.digits(wa_id)

    get_contact(digits) ||
      case create_contact(%{wa_id: digits}) do
        {:ok, contact} ->
          contact

        {:error, _} ->
          get_contact(digits) || raise ArgumentError, "invalid wa_id #{inspect(wa_id)}"
      end
  end

  @doc "Inserts `count` contacts with unique generated numbers."
  def bulk_create(count) when is_integer(count) and count in 1..10_000 do
    existing = MapSet.new(Repo.all(from c in Contact, select: c.wa_id))
    now = DateTime.utc_now()

    Stream.repeatedly(&Ids.contact_wa_id/0)
    |> Stream.reject(&MapSet.member?(existing, &1))
    |> Stream.uniq()
    |> Enum.take(count)
    |> Enum.map(fn wa_id ->
      %{
        wa_id: wa_id,
        profile_name: Names.random(),
        behavior: "normal",
        online: true,
        read_policy: "on_open",
        read_after_ms: 2000,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(&Repo.insert_all(Contact, &1))

    notify({:ok, count})
  end

  def bulk_create(_count), do: {:error, "count must be between 1 and 10000"}

  defp notify({:ok, _} = result) do
    Events.broadcast("config", :contacts_changed)
    result
  end

  defp notify(other), do: other
end
