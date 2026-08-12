defmodule BotArmyCore.NATS.DecoderV2Test do
  use ExUnit.Case, async: true

  alias BotArmyCore.NATS.Decoder

  @fixtures_path "/Users/abby/code/bot_army_v2/protocol/fixtures"

  describe "Dual-Decode (v1 & v2)" do
    test "accepts valid v1 envelope" do
      json = read_fixture("envelope.v1/valid/gtd_task_create.json")
      assert {:ok, _} = Decoder.decode(json)
    end

    test "accepts valid v2 envelope" do
      json = read_fixture("envelope.v2/valid/full.json")
      assert {:ok, _} = Decoder.decode(json)
    end

    test "rejects v2 envelope missing correlation_id" do
      json = read_fixture("envelope.v2/invalid/missing_correlation_id.json")
      assert {:error, {:missing_required_fields, fields}} = Decoder.decode(json)
      assert "correlation_id" in fields
    end

    test "rejects v1 envelope missing schema_version" do
      json = read_fixture("envelope.v1/invalid/missing_schema_version.json")
      assert {:error, {:missing_required_fields, fields}} = Decoder.decode(json)
      assert "schema_version" in fields
    end
  end

  defp read_fixture(path) do
    File.read!(Path.join(@fixtures_path, path))
  end
end
