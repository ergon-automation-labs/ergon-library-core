defmodule BotArmyCore.Factory.EventTest do
  use ExUnit.Case
  @moduletag :schemas

  alias BotArmyCore.Factory.Event

  test "build and decode round-trip" do
    {:ok, env} =
      Event.build(
        "factory.proposal.created",
        :watcher,
        "low",
        "prop-1",
        "",
        %{summary: "x"},
        []
      )

    assert env["event_type"] == "factory.proposal.created"
    assert env["producer"] == "watcher"
    json = Jason.encode!(env)
    assert {:ok, decoded} = Event.decode(json)
    assert decoded["proposal_id"] == "prop-1"
  end

  test "decode rejects invalid producer" do
    {:ok, env} = Event.build("factory.x", :watcher, "low", "p", "", %{}, [])
    bad = %{env | "producer" => "nope"}
    assert {:error, :invalid_producer} = Event.decode(bad)
  end
end
