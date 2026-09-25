defmodule Whelx.Accounts.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]

  schema "settings" do
    field :webhook_retry_profile, :string, default: "fast"
    field :template_approval_policy, :string, default: "manual"
    field :template_review_after_ms, :integer, default: 5000
    field :template_reject_reason, :string, default: "INVALID_FORMAT"
    field :sent_delay_ms, :integer, default: 300
    field :delivered_delay_ms, :integer, default: 700
    field :pair_rate_limit_enabled, :boolean, default: false
    field :pair_rate_limit_burst, :integer, default: 45
    field :pair_rate_limit_interval_ms, :integer, default: 6000
    timestamps()
  end

  @fields [
    :webhook_retry_profile,
    :template_approval_policy,
    :template_review_after_ms,
    :template_reject_reason,
    :sent_delay_ms,
    :delivered_delay_ms
  ]

  @pair_fields [:pair_rate_limit_enabled, :pair_rate_limit_burst, :pair_rate_limit_interval_ms]

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @fields ++ @pair_fields)
    |> validate_required(@fields ++ @pair_fields)
    |> validate_number(:pair_rate_limit_burst, greater_than: 0)
    |> validate_number(:pair_rate_limit_interval_ms, greater_than: 0)
    |> validate_inclusion(:webhook_retry_profile, ~w(fast realistic))
    |> validate_inclusion(:template_approval_policy, ~w(manual auto_approve auto_reject))
    |> validate_number(:template_review_after_ms, greater_than_or_equal_to: 0)
    |> validate_number(:sent_delay_ms, greater_than_or_equal_to: 0)
    |> validate_number(:delivered_delay_ms, greater_than_or_equal_to: 0)
  end
end
