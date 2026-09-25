defmodule Whelx.Chaos.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]
  @sync_codes ~w(130429 131000 http_500 http_503)
  @rates [
    :sync_error_rate,
    :async_fail_rate,
    :reorder_rate,
    :duplicate_rate,
    :drop_rate,
    :batch_rate
  ]

  schema "chaos_profiles" do
    field :seed, :integer, default: 42
    field :preset, :string, default: "off"
    field :latency_min_ms, :integer, default: 0
    field :latency_max_ms, :integer, default: 0
    field :sync_error_rate, :float, default: 0.0
    field :sync_error_codes, {:array, :string}, default: @sync_codes
    field :async_fail_rate, :float, default: 0.0
    field :async_fail_codes, {:array, :integer}, default: [131_000, 131_026, 131_049]
    field :reorder_rate, :float, default: 0.0
    field :duplicate_rate, :float, default: 0.0
    field :drop_rate, :float, default: 0.0
    field :batch_rate, :float, default: 0.0
    field :webhook_extra_delay_ms, :integer, default: 0
    timestamps()
  end

  def sync_codes, do: @sync_codes
  def rates, do: @rates

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :seed,
      :preset,
      :latency_min_ms,
      :latency_max_ms,
      :sync_error_codes,
      :async_fail_codes,
      :webhook_extra_delay_ms | @rates
    ])
    |> validate_required([:seed, :preset])
    |> validate_number(:latency_min_ms, greater_than_or_equal_to: 0)
    |> validate_number(:latency_max_ms, greater_than_or_equal_to: 0)
    |> validate_number(:webhook_extra_delay_ms, greater_than_or_equal_to: 0)
    |> validate_rates()
    |> validate_subset(:sync_error_codes, @sync_codes)
    |> validate_latency_range()
  end

  defp validate_rates(changeset) do
    Enum.reduce(@rates, changeset, fn field, cs ->
      validate_number(cs, field, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    end)
  end

  defp validate_latency_range(changeset) do
    min = get_field(changeset, :latency_min_ms) || 0
    max = get_field(changeset, :latency_max_ms) || 0

    if max < min,
      do: add_error(changeset, :latency_max_ms, "must be >= latency_min_ms"),
      else: changeset
  end
end
