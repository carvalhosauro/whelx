defmodule Whelx.Webhooks do
  @moduledoc "Signed webhook delivery to the configured callback URL, with retries and a log."

  import Ecto.Query
  alias Ecto.Multi
  alias Whelx.{Accounts, Events, Ids, Logs, Repo}
  alias Whelx.Webhooks.{Client, Delivery, DeliveryWorker, Signer}

  @max_attempts 9
  @realistic [15, 60, 300, 900, 3600, 7200, 14_400, 28_800]

  @doc """
  Queues a webhook for the WABA. Records a `skipped` delivery when the app has
  no webhook URL or the WABA has no `subscribed_apps`.

  Options: `:message_wamid`, `:delay_ms`, `:chaos` (default `true`).
  """
  @spec enqueue(String.t(), String.t(), map(), keyword()) :: {:ok, Delivery.t()}
  def enqueue(waba_id, kind, payload, opts \\ []) do
    base = %{waba_id: waba_id, kind: kind, payload: payload, message_wamid: opts[:message_wamid]}

    case skip_reason(waba_id) do
      nil -> insert_pending(base, Keyword.get(opts, :delay_ms, 0))
      reason -> insert_final(base, "skipped", reason)
    end
  end

  @doc false
  def insert_pending(attrs, delay_ms) do
    job_opts =
      if delay_ms > 0,
        do: [scheduled_at: DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)],
        else: []

    Multi.new()
    |> Multi.insert(:delivery, Delivery.changeset(%Delivery{}, Map.put(attrs, :state, "pending")))
    |> Oban.insert(:job, fn %{delivery: d} ->
      DeliveryWorker.new(%{"delivery_id" => d.id}, job_opts)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{delivery: delivery}} -> broadcast({:ok, delivery})
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc false
  def insert_final(attrs, state, reason) do
    %Delivery{}
    |> Delivery.changeset(Map.merge(attrs, %{state: state, last_error: reason}))
    |> Repo.insert()
    |> broadcast()
  end

  defp skip_reason(waba_id) do
    app = Accounts.get_app()
    waba = Accounts.get_waba(waba_id)

    cond do
      is_nil(app) or app.webhook_url in [nil, ""] -> "webhook_url não configurada"
      is_nil(waba) or not waba.subscribed -> "WABA #{waba_id} sem subscribed_apps"
      true -> nil
    end
  end

  @doc "Performs one delivery attempt."
  @spec attempt(Delivery.t(), pos_integer()) :: :ok | {:error, String.t()}
  def attempt(%Delivery{} = delivery, attempt) do
    app = Accounts.get_app!()
    body = Jason.encode!(delivery.payload)
    signature = Signer.sign(body, app.app_secret)

    headers = [
      {"content-type", "application/json"},
      {"x-hub-signature-256", signature},
      {"user-agent", "facebookexternalua"}
    ]

    started = System.monotonic_time(:millisecond)
    result = Client.post(app.webhook_url, body, headers)
    latency = System.monotonic_time(:millisecond) - started

    {state, status, response, error} =
      case result do
        {:ok, %{status: 200, body: resp}} -> {"delivered", 200, resp, nil}
        {:ok, %{status: s, body: resp}} -> {failure_state(attempt), s, resp, "HTTP #{s}"}
        {:error, exception} -> {failure_state(attempt), nil, nil, Exception.message(exception)}
      end

    delivery
    |> Ecto.Changeset.change(
      state: state,
      attempts: attempt,
      last_status: status,
      last_response_body: response |> to_string() |> Logs.truncate(),
      last_error: error,
      latency_ms: latency,
      body: body,
      signature: signature
    )
    |> Repo.update!()
    |> then(&broadcast({:ok, &1}))

    if state == "delivered", do: :ok, else: {:error, error}
  end

  defp failure_state(attempt) when attempt >= @max_attempts, do: "failed"
  defp failure_state(_attempt), do: "retrying"

  @spec backoff_seconds(String.t(), pos_integer()) :: pos_integer()
  def backoff_seconds("realistic", attempt),
    do: Enum.at(@realistic, attempt - 1, List.last(@realistic))

  def backoff_seconds(_fast, attempt), do: Integer.pow(2, attempt - 1)

  @doc "Re-sends the payload of an existing delivery as a new delivery (no chaos)."
  def redeliver(id) do
    case get_delivery(id) do
      nil ->
        {:error, :not_found}

      d ->
        enqueue(d.waba_id, d.kind, d.payload, message_wamid: d.message_wamid, chaos: false)
    end
  end

  @doc "GET handshake against the webhook URL, like Meta's dashboard does."
  def verify do
    app = Accounts.get_app!()
    challenge = Ids.alnum(16)

    if app.webhook_url in [nil, ""] do
      {:error, "webhook_url não configurada"}
    else
      params = %{
        "hub.mode" => "subscribe",
        "hub.verify_token" => app.verify_token,
        "hub.challenge" => challenge
      }

      case Client.get(app.webhook_url, params) do
        {:ok, %{status: status, body: body}} ->
          body = to_string(body)

          {:ok,
           %{status: status, ok: status == 200 and String.trim(body) == challenge, body: body}}

        {:error, exception} ->
          {:error, Exception.message(exception)}
      end
    end
  end

  def get_delivery(id), do: Repo.get(Delivery, id)

  def list_deliveries(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Delivery
    |> order_by(desc: :id)
    |> limit(^limit)
    |> filter(:message_wamid, opts[:message_wamid])
    |> filter(:state, opts[:state])
    |> Repo.all()
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [d], field(d, ^field) == ^value)

  defp broadcast({:ok, delivery} = result) do
    Events.broadcast("deliveries", {:delivery, delivery})
    result
  end

  defp broadcast(other), do: other
end
