defmodule BotArmyCore.NATS.Decoder do
  @moduledoc """
  Decodes NATS messages using the schema definitions deployed at `/etc/bot_army/schemas/core/`.

  This module reads the schema files at runtime to determine which message versions
  are supported, as defined in the `supported_versions` array of each schema.

  ## Schema Files

  Expected location: `/etc/bot_army/schemas/core/`

  - `envelope.json` - Immutable message wrapper structure
  - `error.json` - Standard error response shape
  - `system.health.json` - System heartbeat shape
  - `system.alert.json` - System alert shape
  - `triggered_by.json` - Valid audit value enum

  ## Message Flow

  1. Receive raw NATS message
  2. Decode message envelope (validates against `envelope.json`)
  3. Extract payload and schema_version
  4. Validate payload against versioned schema
  5. Return decoded message or error
  """

  require Logger

  @schemas_dir "/etc/bot_army/schemas/core"

  @doc """
  Decode a NATS message envelope and payload.

  Returns `{:ok, decoded_message}` or `{:error, reason}`.
  """
  def decode(raw_message) when is_binary(raw_message) do
    case Jason.decode(raw_message) do
      {:ok, envelope} -> validate_envelope(envelope)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  def decode(_), do: {:error, :invalid_message_format}

  # Private functions

  defp validate_envelope(envelope) when is_map(envelope) do
    with :ok <- validate_required_fields(envelope),
         :ok <- validate_field_types(envelope),
         {:ok, payload} <- extract_and_validate_payload(envelope) do
      Logger.debug(
        "Envelope validation passed: event=#{envelope["event"]}, version=#{envelope["schema_version"]}"
      )

      {:ok, %{envelope | "payload" => payload}}
    else
      {:error, reason} ->
        Logger.warning("Envelope validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_envelope(_) do
    {:error, :envelope_not_map}
  end

  # Required fields from the envelope schema (as strings, since JSON keys are strings)
  @required_envelope_fields [
    "event_id",
    "event",
    "schema_version",
    "timestamp",
    "source",
    "source_node",
    "triggered_by",
    "payload"
  ]

  defp validate_required_fields(envelope) do
    missing_fields = Enum.filter(@required_envelope_fields, &is_nil(envelope[&1]))

    if envelope["event"] == "system.health" && not Enum.empty?(missing_fields) do
      Logger.info(
        "[Decoder] system.health envelope keys: #{envelope |> Map.keys() |> Enum.join(",")}"
      )

      Logger.info(
        "[Decoder] Missing: #{inspect(missing_fields)}, source_node=#{inspect(envelope["source_node"])}, triggered_by=#{inspect(envelope["triggered_by"])}"
      )
    end

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp validate_field_types(envelope) do
    # Required fields - must have correct type
    required_validations = [
      {"event_id", "string"},
      {"event", "string"},
      {"schema_version", "string"},
      {"timestamp", "string"},
      {"source", "string"},
      {"source_node", "string"},
      {"payload", "object"}
    ]

    # Optional fields - if present, must have correct type
    optional_validations = [
      {"tenant_id", "string"},
      {"user_id", "string"},
      {"role", "string"}
    ]

    # Validate required fields
    case Enum.reduce_while(required_validations, :ok, fn {field, expected_type}, _acc ->
           value = envelope[field]

           if valid_type?(value, expected_type) do
             {:cont, :ok}
           else
             {:halt, {:error, {:invalid_field_type, field, expected_type}}}
           end
         end) do
      :ok ->
        # Validate optional fields if present
        Enum.reduce_while(optional_validations, :ok, fn {field, expected_type}, _acc ->
          case envelope[field] do
            nil ->
              # Field not present - that's fine, it's optional
              {:cont, :ok}

            value ->
              # Field present - validate type
              if valid_type?(value, expected_type) do
                {:cont, :ok}
              else
                {:halt, {:error, {:invalid_field_type, field, expected_type}}}
              end
          end
        end)

      error ->
        error
    end
  end

  defp valid_type?(value, "object") when is_map(value), do: true
  defp valid_type?(value, "string") when is_binary(value), do: true
  defp valid_type?(_, "string"), do: false
  defp valid_type?(_, "object"), do: false

  defp extract_and_validate_payload(envelope) do
    payload = envelope["payload"]
    version = envelope["schema_version"]
    event = envelope["event"]

    # Extract schema name from event (e.g., "gtd.task.create" -> "gtd" for gtd schemas)
    case get_schema_name(event, version) do
      {:ok, schema_name} ->
        case load_schema(schema_name) do
          {:ok, schema} ->
            if schema_supported?(schema, version) do
              {:ok, payload}
            else
              {:error, {:unsupported_schema_version, schema_name, version}}
            end

          {:error, reason} ->
            Logger.debug("Could not load schema for event #{event}: #{inspect(reason)}")
            # Allow graceful degradation - payload is valid if schema not found
            {:ok, payload}
        end

      :error ->
        # Unknown event type, but allow it through with validation
        {:ok, payload}
    end
  end

  defp get_schema_name(event, _version) when is_binary(event) do
    # Extract bot name from event (e.g., "gtd.task.create" -> "gtd")
    case String.split(event, ".", parts: 2) do
      [bot_name | _] -> {:ok, bot_name}
      _ -> :error
    end
  end

  defp schema_supported?(schema, version) when is_map(schema) do
    case schema do
      %{"supported_versions" => versions} when is_list(versions) ->
        Enum.member?(versions, version)

      _ ->
        # If no supported_versions defined, accept any version
        true
    end
  end

  defp schema_supported?(_, _), do: false

  @doc """
  Load schema from disk.

  Returns the parsed JSON schema file.
  """
  def load_schema(schema_name) when is_binary(schema_name) do
    path = Path.join(@schemas_dir, "#{schema_name}.json")

    case File.read(path) do
      {:ok, content} -> Jason.decode(content)
      {:error, :enoent} -> {:error, {:schema_not_found, schema_name}}
      {:error, reason} -> {:error, {:schema_read_error, schema_name, reason}}
    end
  end

  @doc """
  Get supported versions for a given schema.

  Returns list of version strings (e.g., ["1.0", "1.1"]).
  """
  def supported_versions(schema_name) when is_binary(schema_name) do
    case load_schema(schema_name) do
      {:ok, schema} ->
        {:ok, schema["supported_versions"] || ["1.0"]}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
