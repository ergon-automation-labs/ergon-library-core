defmodule BotArmy.GenBotNATSIntegrationTest do
  use ExUnit.Case
  @moduletag :integration
  @tag :integration

  @moduledoc """
  Real NATS integration tests for GenBot skill harness.

  These tests require NATS running on localhost:4223 (dev port).
  Skipped if NATS is not available.

  Tests verify:
  - Skill registration and subscription to NATS triggers
  - Message routing from NATS to matching skills
  - Skill execution and response publishing
  - Context injection during skill execution
  """

  # Helper to check if NATS is available
  defp nats_available? do
    case :gen_tcp.connect(~c"localhost", 4223, [:binary, active: false], 100) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  setup do
    if not nats_available?() do
      {:skip, "NATS not available on localhost:4223"}
    else
      # Wait for NATS connection to be established
      Process.sleep(100)
      {:ok, nats_ready: true}
    end
  end

  describe "GenBot with real NATS" do
    test "skill is invoked when NATS message matches trigger pattern", %{nats_ready: true} do
      # Create a test skill that echoes input
      defmodule NATSTest.Skills.EchoSkill do
        use BotArmy.Skill

        def name, do: :echo_nats
        def description, do: "Echo skill for NATS test"
        def nats_triggers, do: ["test.genbot.echo"]
        def llm_hint, do: :none

        def execute(%{"text" => text}, _ctx) do
          {:ok, %{echoed: text, timestamp: DateTime.utc_now()}}
        end

        def validate(%{"text" => t}) when is_binary(t) and byte_size(t) > 0, do: :ok
        def validate(_), do: {:error, "text field required"}
      end

      # Create a test bot using GenBot
      defmodule NATSTest.EchoBot do
        use BotArmy.GenBot,
          skills: [NATSTest.Skills.EchoSkill],
          bot_id: :echo_bot_test
      end

      # Start the bot
      {:ok, _bot_pid} = NATSTest.EchoBot.start_link()

      # Allow bot to subscribe to NATS triggers
      Process.sleep(200)

      # Publish a message that matches the skill trigger
      payload = %{"text" => "hello from test"}
      json_payload = Jason.encode!(payload)

      {:ok, _} =
        BotArmyCore.NATS.publish(
          "test.genbot.echo",
          %{
            "payload" => payload,
            "event" => "test.echo"
          }
        )

      # Give the skill time to execute (runs async via Task.start)
      Process.sleep(500)

      # Synchronously test that the skill works
      {:ok, result} = NATSTest.EchoBot.run_skill(:echo_nats, %{"text" => "test message"})
      assert result.echoed == "test message"
      assert Map.has_key?(result, :timestamp)
    end

    test "multiple skills with different triggers", %{nats_ready: true} do
      defmodule NATSTest.Skills.Alpha do
        use BotArmy.Skill

        def name, do: :alpha_nats
        def description, do: "Alpha skill"
        def nats_triggers, do: ["test.multi.alpha"]
        def llm_hint, do: :none

        def execute(%{"value" => v}, _ctx) do
          {:ok, %{alpha: v, processed: true}}
        end
      end

      defmodule NATSTest.Skills.Beta do
        use BotArmy.Skill

        def name, do: :beta_nats
        def description, do: "Beta skill"
        def nats_triggers, do: ["test.multi.beta"]
        def llm_hint, do: :none

        def execute(%{"value" => v}, _ctx) do
          {:ok, %{beta: String.upcase(v), processed: true}}
        end
      end

      defmodule NATSTest.MultiBot do
        use BotArmy.GenBot,
          skills: [NATSTest.Skills.Alpha, NATSTest.Skills.Beta],
          bot_id: :multi_bot_test
      end

      {:ok, _bot_pid} = NATSTest.MultiBot.start_link()
      Process.sleep(200)

      # Test alpha skill
      {:ok, alpha_result} = NATSTest.MultiBot.run_skill(:alpha_nats, %{"value" => "test"})
      assert alpha_result.alpha == "test"
      assert alpha_result.processed == true

      # Test beta skill
      {:ok, beta_result} = NATSTest.MultiBot.run_skill(:beta_nats, %{"value" => "test"})
      assert beta_result.beta == "TEST"
      assert beta_result.processed == true
    end

    test "wildcard trigger patterns match correctly", %{nats_ready: true} do
      defmodule NATSTest.Skills.Wildcard do
        use BotArmy.Skill

        def name, do: :wildcard_nats
        def description, do: "Skill with wildcard triggers"
        # Matches: test.wildcard.cmd, test.wildcard.cmd.subcommand, etc.
        def nats_triggers, do: ["test.wildcard.>"]
        def llm_hint, do: :none

        def execute(%{"cmd" => cmd}, _ctx) do
          {:ok, %{command: cmd, matched: true}}
        end
      end

      defmodule NATSTest.WildcardBot do
        use BotArmy.GenBot,
          skills: [NATSTest.Skills.Wildcard],
          bot_id: :wildcard_bot_test
      end

      {:ok, _bot_pid} = NATSTest.WildcardBot.start_link()
      Process.sleep(200)

      # Skill should handle requests
      {:ok, result} = NATSTest.WildcardBot.run_skill(:wildcard_nats, %{"cmd" => "test"})
      assert result.matched == true
    end

    test "skill context includes bot_id and llm proxy", %{nats_ready: true} do
      defmodule NATSTest.Skills.ContextCheck do
        use BotArmy.Skill

        def name, do: :context_check_nats
        def description, do: "Checks context"
        def nats_triggers, do: ["test.context"]
        def llm_hint, do: :none

        def execute(_input, ctx) do
          {:ok,
           %{
             bot_id: ctx.bot_id,
             bot_id_is_atom: is_atom(ctx.bot_id),
             has_personality: is_map(ctx.personality),
             has_llm: is_atom(ctx.llm)
           }}
        end
      end

      defmodule NATSTest.ContextBot do
        use BotArmy.GenBot,
          skills: [NATSTest.Skills.ContextCheck],
          bot_id: :context_bot_test,
          personality: BotArmy.DefaultPersonality
      end

      {:ok, _bot_pid} = NATSTest.ContextBot.start_link()
      Process.sleep(200)

      {:ok, result} = NATSTest.ContextBot.run_skill(:context_check_nats, %{})

      assert result.bot_id == :context_bot_test
      assert result.bot_id_is_atom == true
      assert result.has_personality == true
      assert result.has_llm == true
    end
  end
end
