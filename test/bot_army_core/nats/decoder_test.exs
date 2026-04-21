defmodule BotArmyCore.NATS.DecoderTest do
  use ExUnit.Case
  @moduletag :nats

  alias BotArmyCore.NATS.Decoder

  describe "decode/1 - JSON parsing" do
    test "returns error on invalid JSON" do
      {:error, {:json_decode_error, _reason}} = Decoder.decode("invalid json")
    end

    test "returns error on non-binary input" do
      {:error, :invalid_message_format} = Decoder.decode(123)
    end

    test "returns error when message is not a map" do
      invalid_json = Jason.encode!("just a string")
      {:error, :envelope_not_map} = Decoder.decode(invalid_json)
    end
  end

  describe "decode/1 - envelope validation" do
    test "validates required envelope fields" do
      incomplete_message = %{
        "event" => "test.event",
        "schema_version" => "1.0"
      }

      {:error, {:missing_required_fields, missing}} =
        Decoder.decode(Jason.encode!(incomplete_message))

      assert "event_id" in missing
      assert "timestamp" in missing
    end

    test "validates field types" do
      invalid_message = %{
        "event_id" => "uuid",
        "event" => "test.event",
        # Should be string
        "schema_version" => 1.0,
        "timestamp" => "2026-03-01T12:00:00Z",
        "source" => "test",
        "source_node" => "air",
        "triggered_by" => "user",
        "payload" => %{}
      }

      {:error, {:invalid_field_type, "schema_version", "string"}} =
        Decoder.decode(Jason.encode!(invalid_message))
    end

    test "accepts valid complete envelope" do
      valid_message = %{
        "event_id" => "550e8400-e29b-41d4-a716-446655440000",
        "event" => "test.event",
        "schema_version" => "1.0",
        "timestamp" => "2026-03-01T12:00:00Z",
        "source" => "test_bot",
        "source_node" => "air",
        "triggered_by" => "user",
        "payload" => %{"test" => "data"}
      }

      {:ok, decoded} = Decoder.decode(Jason.encode!(valid_message))
      assert decoded["event"] == "test.event"
      assert decoded["payload"] == %{"test" => "data"}
    end
  end

  describe "load_schema/1" do
    test "returns error when schema file not found" do
      {:error, {:schema_not_found, "nonexistent"}} = Decoder.load_schema("nonexistent")
    end
  end

  describe "supported_versions/1" do
    test "returns error for nonexistent schema" do
      {:error, {:schema_not_found, "nonexistent"}} = Decoder.supported_versions("nonexistent")
    end
  end

  describe "schema version validation" do
    test "accepts message with any version when schema not available" do
      # When schema file is not found, decoder allows the message through
      valid_message = %{
        "event_id" => "550e8400-e29b-41d4-a716-446655440000",
        "event" => "unknown.event",
        "schema_version" => "99.99",
        "timestamp" => "2026-03-01T12:00:00Z",
        "source" => "test_bot",
        "source_node" => "air",
        "triggered_by" => "user",
        "payload" => %{"data" => "value"}
      }

      {:ok, decoded} = Decoder.decode(Jason.encode!(valid_message))
      assert decoded["schema_version"] == "99.99"
    end
  end
end
