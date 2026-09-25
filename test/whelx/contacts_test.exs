defmodule Whelx.ContactsTest do
  use Whelx.DataCase
  alias Whelx.Contacts

  test "create_contact/1 generates a BR wa_id and a name when missing" do
    {:ok, contact} = Contacts.create_contact(%{})
    assert contact.wa_id =~ ~r/^55119\d{8}$/
    assert is_binary(contact.profile_name) and contact.profile_name != ""
    assert contact.behavior == "normal"
    assert contact.online
    assert contact.read_policy == "on_open"
  end

  test "create_contact/1 normalizes and validates wa_id" do
    {:ok, contact} = Contacts.create_contact(%{wa_id: "+55 (11) 98888-7777", profile_name: "Ana"})
    assert contact.wa_id == "5511988887777"
    assert {:error, cs} = Contacts.create_contact(%{wa_id: "123"})
    assert errors_on(cs).wa_id != []
    assert {:error, cs} = Contacts.create_contact(%{wa_id: "5511988887777"})
    assert errors_on(cs).wa_id != []
  end

  test "find_or_create_contact/1 is idempotent on formatted numbers" do
    a = Contacts.find_or_create_contact("+55 11 97777-6666")
    b = Contacts.find_or_create_contact("5511977776666")
    assert a.wa_id == b.wa_id
    assert length(Contacts.list_contacts()) == 1
  end

  test "bulk_create/1 inserts N unique contacts" do
    {:ok, 250} = Contacts.bulk_create(250)
    contacts = Contacts.list_contacts()
    assert length(contacts) == 250
    assert contacts |> Enum.map(& &1.wa_id) |> Enum.uniq() |> length() == 250
  end

  test "update_contact/2 validates behavior and read policy" do
    {:ok, contact} = Contacts.create_contact(%{})

    assert {:ok, %{behavior: "invalid_number"}} =
             Contacts.update_contact(contact, %{behavior: "invalid_number"})

    assert {:error, _} = Contacts.update_contact(contact, %{read_policy: "sometimes"})
  end
end
