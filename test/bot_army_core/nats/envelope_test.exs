defmodule BotArmyLibraryCore.NATS.EnvelopeTest do
  use ExUnit.Case

  @moduletag :nats

  alias BotArmyLibraryCore.NATS.Decoder
  alias BotArmyLibraryCore.NATS.Envelope

  doctest Envelope

  describe "build/3 - decoder contract" do
    test "every generated envelope satisfies the shared decoder" do
      envelope =
        Envelope.build(
          "gossip.tavern.narrated",
          %{"text" => "The tavern stirs.", "tavern" => true},
          source: "bot_army_synapse",
          triggered_by: "scheduler"
        )

      assert {:ok, decoded} = Decoder.decode(Jason.encode!(envelope))
      assert decoded["event"] == "gossip.tavern.narrated"
      assert decoded["source"] == "bot_army_synapse"
      assert decoded["triggered_by"] == "scheduler"
      assert decoded["payload"] == %{"text" => "The tavern stirs.", "tavern" => true}
    end

    test "sets all eight required fields, none nil" do
      envelope = Envelope.build("test.event", %{"k" => "v"})

      for field <-
            ~w(event_id event schema_version timestamp source source_node triggered_by payload) do
        assert Map.has_key?(envelope, field), "missing #{field}"
        refute is_nil(envelope[field]), "#{field} is nil"
      end
    end

    test "generates a distinct uuid per envelope" do
      a = Envelope.build("test.event", %{})
      b = Envelope.build("test.event", %{})

      assert a["event_id"] =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
      refute a["event_id"] == b["event_id"]
    end
  end

  describe "build/3 - defaults and overrides" do
    test "defaults to this node, version 1.0 and triggered_by system" do
      envelope = Envelope.build("test.event", %{})

      assert envelope["source_node"] == Atom.to_string(node())
      assert envelope["schema_version"] == "1.0"
      assert envelope["triggered_by"] == "system"
      assert envelope["source"] == "unknown"
    end

    test "accepts overrides for identity fields" do
      envelope =
        Envelope.build("test.event", %{},
          event_id: "fixed-id",
          timestamp: "2026-01-01T00:00:00Z",
          schema_version: "2.0",
          source: "some_bot",
          source_node: "mini",
          triggered_by: "user"
        )

      assert envelope["event_id"] == "fixed-id"
      assert envelope["timestamp"] == "2026-01-01T00:00:00Z"
      assert envelope["schema_version"] == "2.0"
      assert envelope["source"] == "some_bot"
      assert envelope["source_node"] == "mini"
      assert envelope["triggered_by"] == "user"
    end

    test "omits optional routing fields unless supplied" do
      bare = Envelope.build("test.event", %{})

      refute Map.has_key?(bare, "tenant_id")
      refute Map.has_key?(bare, "conversation_id")

      full =
        Envelope.build("test.event", %{},
          tenant_id: "tenant-1",
          user_id: "user-1",
          conversation_id: "conv-1",
          correlation_id: "corr-1"
        )

      assert full["tenant_id"] == "tenant-1"
      assert full["user_id"] == "user-1"
      assert full["conversation_id"] == "conv-1"
      assert full["correlation_id"] == "corr-1"
    end

    test "passes the payload through untouched" do
      payload = %{"text" => "hello", "nested" => %{"a" => 1}, "list" => ["x"]}
      assert Envelope.build("test.event", payload)["payload"] == payload
    end
  end
end
