defmodule BotArmyLibraryCore.Factory.Event do
  @moduledoc """
  Canonical factory event envelope (see `schemas/factory/factory_event.schema.json`).

  All `factory.*` NATS messages use this shape at the top level.
  """

  @schema_version "1.0.0"

  @producers ~w(watcher fixer breaker synapse human_override)
  @risk_classes ~w(low medium high)

  @doc """
  Builds an envelope. Returns `{:ok, map}` with string keys suitable for `Jason.encode!/1`.
  """
  def build(event_type, producer, risk_class, proposal_id, decision_id, payload, opts \\ [])
      when is_binary(event_type) and is_binary(proposal_id) do
    with :ok <- validate_event_type(event_type),
         {:ok, producer_str} <- normalize_producer(producer),
         {:ok, risk_str} <- normalize_risk_class(risk_class) do
      now = Keyword.get(opts, :now, DateTime.utc_now())
      ttl_sec = Keyword.get(opts, :ttl_seconds, 86_400)
      expires = DateTime.add(now, ttl_sec, :second)
      did = if decision_id in [nil, ""], do: "", else: decision_id

      {:ok,
       %{
         "event_id" => Keyword.get(opts, :event_id, Ecto.UUID.generate()),
         "schema_version" => Keyword.get(opts, :schema_version, @schema_version),
         "event_type" => event_type,
         "created_at" => format_dt(now),
         "expires_at" => format_dt(expires),
         "proposal_id" => proposal_id,
         "decision_id" => did,
         "producer" => producer_str,
         "risk_class" => risk_str,
         "payload" => stringify_payload(payload)
       }}
    end
  end

  @doc """
  Decodes JSON string or map into a validated envelope map (string keys) or `{:error, reason}`.
  """
  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> decode(map)
      {:ok, _} -> {:error, :not_object}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def decode(map) when is_map(map) do
    map = stringify_keys(map)

    required =
      ~w(event_id schema_version event_type created_at expires_at proposal_id decision_id producer risk_class payload)

    case Enum.filter(required, &(not Map.has_key?(map, &1))) do
      [] ->
        with {:ok, _} <- normalize_producer(map["producer"]),
             {:ok, _} <- normalize_risk_class(map["risk_class"]),
             true <- String.starts_with?(map["event_type"], "factory."),
             true <- is_map(map["payload"]) do
          {:ok, map}
        else
          false -> {:error, :invalid_envelope}
          {:error, _} = err -> err
        end

      missing ->
        {:error, {:missing_fields, missing}}
    end
  end

  @doc "Returns the inner payload map with string keys."
  def payload_map(%{} = envelope) when is_map(envelope) do
    envelope |> Map.get("payload", %{}) |> stringify_keys()
  end

  defp validate_event_type(et) do
    if String.starts_with?(et, "factory."), do: :ok, else: {:error, :invalid_event_type}
  end

  defp stringify_payload(p) when is_map(p), do: stringify_keys(p)
  defp stringify_payload(p), do: %{"value" => p}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), deep_stringify(v)}
      {k, v} when is_binary(k) -> {k, deep_stringify(v)}
    end)
  end

  defp deep_stringify(%{} = m), do: stringify_keys(m)
  defp deep_stringify(v), do: v

  defp format_dt(%DateTime{} = dt),
    do: dt |> DateTime.truncate(:second) |> DateTime.to_iso8601() |> String.replace("+00:00", "Z")

  defp normalize_producer(p) when p in @producers, do: {:ok, p}
  defp normalize_producer(p) when is_atom(p), do: normalize_producer(Atom.to_string(p))
  defp normalize_producer(_), do: {:error, :invalid_producer}

  defp normalize_risk_class(r) when r in @risk_classes, do: {:ok, r}
  defp normalize_risk_class(r) when is_atom(r), do: normalize_risk_class(Atom.to_string(r))
  defp normalize_risk_class(_), do: {:error, :invalid_risk_class}
end
