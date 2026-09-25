defmodule Whelx.Templates.Template do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  @statuses ~w(PENDING APPROVED REJECTED PAUSED DISABLED)

  schema "templates" do
    field :waba_id, :string
    field :name, :string
    field :language, :string
    field :category, :string
    field :components, {:array, :map}, default: []
    field :status, :string, default: "PENDING"
    field :rejected_reason, :string
    timestamps()
  end

  def statuses, do: @statuses

  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :id,
      :waba_id,
      :name,
      :language,
      :category,
      :components,
      :status,
      :rejected_reason
    ])
    |> validate_required([:id, :waba_id, :name, :language, :category, :components, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:waba_id, :name, :language])
  end
end
