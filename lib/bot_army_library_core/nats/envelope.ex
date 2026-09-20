defmodule BotArmyLibraryCore.NATS.Envelope do
  @moduledoc """
  Builds the standard Bot Army NATS envelope that `BotArmyLibraryCore.NATS.Decoder` accepts.

  The decoder requires eight fields on every envelope: `event_id`, `event`,
  `schema_version`, `timestamp`, `source`, `source_node`, `triggered_by` and
  `payload`. Publishers used to hand-roll that map, and the hand-rolled copies
  drifted. Five publishers of `gossip.tavern.narrated` omitted `source_node` and
  `triggered_by` (or `event_id`/`schema_version`/`payload` outright), so every
  subscriber rejected the narration with
  `{:missing_required_fields, ["source_node", "triggered_by"]}`: the tavern feed
  was silently dropped and subscriber logs filled with warnings.

  Build envelopes here instead of by hand. The output is pinned to the decoder by
  `BotArmyLibraryCore.NATS.EnvelopeTest`, so a builder and decoder cannot drift
  apart unnoticed again.

  ## Example

      iex> envelope =
      ...>   BotArmyLibraryCore.NATS.Envelope.build(
      ...>     "gossip.tavern.narrated",
      ...>     %{"text" => "The tavern stirs."},
      ...>     source: "bot_army_synapse",
      ...>     triggered_by: "scheduler"
      ...>   )
      iex> {envelope["event"], envelope["source"], envelope["triggered_by"]}
      {"gossip.tavern.narrated", "bot_army_synapse", "scheduler"}

  """

  @schema_version "1.0"
  @source "unknown"
  @triggered_by "system"

  @optional_fields [:tenant_id, :user_id, :conversation_id, :correlation_id]

  @doc """
  Build an envelope for `event` carrying `payload`.

  All eight decoder-required fields are set by construction.

  ## Options

    - `:source` — publishing bot or component (default `"#{@source}"`)
    - `:source_node` — node name (default `node()`)
    - `:triggered_by` — audit value from `triggered_by.json` (default `"#{@triggered_by}"`)
    - `:event_id` — override the generated UUIDv4
    - `:timestamp` — override the current ISO8601 timestamp
    - `:schema_version` — override `"#{@schema_version}"`
    - `:tenant_id`, `:user_id`, `:conversation_id`, `:correlation_id` — included when present
  """
  def build(event, payload, opts \\ []) when is_binary(event) and is_map(payload) do
    envelope = %{
      "event_id" => opts[:event_id] || UUID.uuid4(),
      "event" => event,
      "schema_version" => opts[:schema_version] || @schema_version,
      "timestamp" => opts[:timestamp] || DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => opts[:source] || @source,
      "source_node" => opts[:source_node] || Atom.to_string(node()),
      "triggered_by" => opts[:triggered_by] || @triggered_by,
      "payload" => payload
    }

    Enum.reduce(@optional_fields, envelope, fn key, acc ->
      case opts[key] do
        nil -> acc
        value -> Map.put(acc, Atom.to_string(key), value)
      end
    end)
  end
end
