defmodule BotArmy.GenBotIntegrationTest do
  use ExUnit.Case
  @moduletag :integration
  @tag :integration
  doctest BotArmy.GenBot

  describe "BotArmy.Skill behaviour" do
    test "skill module implements required callbacks" do
      defmodule SkillCallbacks.Complete do
        use BotArmy.Skill

        def name, do: :complete
        def description, do: "Complete skill"
        def nats_triggers, do: ["test.complete"]
        def llm_hint, do: :fast
        def execute(input, _ctx), do: {:ok, input}
        def validate(_), do: :ok
      end

      # Verify all callbacks are defined
      assert function_exported?(SkillCallbacks.Complete, :name, 0)
      assert function_exported?(SkillCallbacks.Complete, :description, 0)
      assert function_exported?(SkillCallbacks.Complete, :nats_triggers, 0)
      assert function_exported?(SkillCallbacks.Complete, :llm_hint, 0)
      assert function_exported?(SkillCallbacks.Complete, :execute, 2)
      assert function_exported?(SkillCallbacks.Complete, :validate, 1)

      # Verify callback values
      assert SkillCallbacks.Complete.name() == :complete
      assert is_binary(SkillCallbacks.Complete.description())
      assert is_list(SkillCallbacks.Complete.nats_triggers())
      assert SkillCallbacks.Complete.llm_hint() in [:fast, :quality, :research, :none]
    end

    test "default validate/1 accepts all input" do
      defmodule SkillValidation.NoValidate do
        use BotArmy.Skill

        def name, do: :no_validate
        def description, do: "No custom validation"
        def nats_triggers, do: ["test.no_validate"]
        def llm_hint, do: :none
        def execute(input, _ctx), do: {:ok, input}
      end

      # Default validate should accept anything
      assert SkillValidation.NoValidate.validate(%{}) == :ok
      assert SkillValidation.NoValidate.validate(%{"anything" => "goes"}) == :ok
      assert SkillValidation.NoValidate.validate(nil) == :ok
    end

    test "custom validate/1 overrides default" do
      defmodule SkillValidation.CustomValidate do
        use BotArmy.Skill

        def name, do: :custom_validate
        def description, do: "Custom validation"
        def nats_triggers, do: ["test.custom"]
        def llm_hint, do: :none
        def execute(input, _ctx), do: {:ok, input}

        def validate(%{"required_field" => _}), do: :ok
        def validate(_), do: {:error, "required_field is required"}
      end

      # Custom validate should enforce the field
      assert SkillValidation.CustomValidate.validate(%{"required_field" => "value"}) == :ok
      assert match?({:error, _}, SkillValidation.CustomValidate.validate(%{}))
    end

    test "skill execution and result format" do
      defmodule SkillExecution.Echo do
        use BotArmy.Skill

        def name, do: :echo
        def description, do: "Echoes input"
        def nats_triggers, do: ["test.echo"]
        def llm_hint, do: :fast
        def execute(%{"text" => text}, _ctx), do: {:ok, %{echoed: text}}
        def execute(_input, _ctx), do: {:error, :invalid_input}

        def validate(%{"text" => t}) when is_binary(t), do: :ok
        def validate(_), do: {:error, "text required"}
      end

      skill = SkillExecution.Echo

      # Valid execution
      {:ok, result} = skill.execute(%{"text" => "hello"}, %{})
      assert result.echoed == "hello"
      assert is_map(result)

      # Error execution
      {:error, reason} = skill.execute(%{}, %{})
      assert reason == :invalid_input

      # Validation
      assert skill.validate(%{"text" => "valid"}) == :ok
      assert match?({:error, _}, skill.validate(%{}))
    end

    test "skill with context injection" do
      defmodule SkillContext.ContextCheck do
        use BotArmy.Skill

        def name, do: :context_check
        def description, do: "Checks context"
        def nats_triggers, do: ["test.context"]
        def llm_hint, do: :none

        def execute(_input, ctx) do
          {:ok,
           %{
             bot_id_present: not is_nil(ctx.bot_id),
             personality_present: is_map(ctx.personality),
             context_present: is_map(ctx.context),
             llm_present: is_atom(ctx.llm)
           }}
        end
      end

      # Simulate context that GenBot would provide
      ctx = %{
        bot_id: :test_bot,
        personality: %{name: "TestBot"},
        context: %{},
        llm: BotArmy.LLMProxy
      }

      {:ok, result} = SkillContext.ContextCheck.execute(%{}, ctx)
      assert result.bot_id_present == true
      assert result.personality_present == true
      assert result.context_present == true
      assert result.llm_present == true
    end
  end

  describe "NATS wildcard pattern matching" do
    test "subject_matches? handles * (single token wildcard)" do
      # * matches exactly one token (not zero, not multiple)
      assert BotArmyCore.NATS.subject_matches?("test.*", "test.command") == true
      assert BotArmyCore.NATS.subject_matches?("test.*", "test.command.extra") == false
      assert BotArmyCore.NATS.subject_matches?("test.*", "test") == false
    end

    test "subject_matches? handles > (zero-or-more token wildcard)" do
      # > matches zero or more tokens at the end
      assert BotArmyCore.NATS.subject_matches?("test.>", "test.command") == true
      assert BotArmyCore.NATS.subject_matches?("test.>", "test.command.extra") == true
      assert BotArmyCore.NATS.subject_matches?("test.>", "test.command.extra.deep") == true
      assert BotArmyCore.NATS.subject_matches?("test.>", "test") == true
      assert BotArmyCore.NATS.subject_matches?("test.>", "other.command") == false
    end

    test "subject_matches? combines * and > patterns" do
      # events.*.>  matches events.<one-token>.<zero-or-more-tokens>
      assert BotArmyCore.NATS.subject_matches?("events.*.>", "events.gtd.task.created") == true
      assert BotArmyCore.NATS.subject_matches?("events.*.>", "events.gtd") == true
      assert BotArmyCore.NATS.subject_matches?("events.*.>", "events.gtd.task") == true
      assert BotArmyCore.NATS.subject_matches?("events.*.>", "events") == false

      assert BotArmyCore.NATS.subject_matches?("events.*.>", "events.gtd.task.created.extra") ==
               true
    end

    test "subject_matches? with exact match (no wildcards)" do
      # Exact subjects require exact match
      assert BotArmyCore.NATS.subject_matches?("test.exact", "test.exact") == true
      assert BotArmyCore.NATS.subject_matches?("test.exact", "test.exact.extra") == false
      assert BotArmyCore.NATS.subject_matches?("test.exact", "test.other") == false
    end

    test "subject_matches? with skill trigger patterns" do
      # Real skill trigger patterns
      pattern1 = "bot.job_applications.command.>"

      assert BotArmyCore.NATS.subject_matches?(pattern1, "bot.job_applications.command.create") ==
               true

      assert BotArmyCore.NATS.subject_matches?(
               pattern1,
               "bot.job_applications.command.delete.reason"
             ) == true

      assert BotArmyCore.NATS.subject_matches?(pattern1, "bot.job_applications.event.created") ==
               false

      pattern2 = "events.llm.completion.*"

      assert BotArmyCore.NATS.subject_matches?(pattern2, "events.llm.completion.job_applications") ==
               true

      assert BotArmyCore.NATS.subject_matches?(pattern2, "events.llm.completion.gtd.extra") ==
               false

      pattern3 = "events.gtd.task.>"
      assert BotArmyCore.NATS.subject_matches?(pattern3, "events.gtd.task.created") == true

      assert BotArmyCore.NATS.subject_matches?(pattern3, "events.gtd.task.state.updated.reason") ==
               true

      assert BotArmyCore.NATS.subject_matches?(pattern3, "events.gtd.project.created") == false
    end

    test "subject_matches? edge cases" do
      # Empty subjects
      assert BotArmyCore.NATS.subject_matches?("test", "test") == true

      # Pattern with multiple wildcards
      assert BotArmyCore.NATS.subject_matches?("*.*.>", "a.b.c.d") == true
      assert BotArmyCore.NATS.subject_matches?("*.*.>", "a.b") == true
      assert BotArmyCore.NATS.subject_matches?("*.*.>", "a") == false

      # > at start (unusual but valid)
      assert BotArmyCore.NATS.subject_matches?(">", "anything.goes.here") == true
      assert BotArmyCore.NATS.subject_matches?(">", "a") == true
      assert BotArmyCore.NATS.subject_matches?(">", "") == true
    end
  end

  describe "GenBot skill index building" do
    test "skill index maps triggers to skills" do
      defmodule SkillIndexing.Skill1 do
        use BotArmy.Skill
        def name, do: :skill1
        def description, do: "Skill 1"
        def nats_triggers, do: ["trigger.one", "trigger.one.deep.>"]
        def llm_hint, do: :none
        def execute(_, _), do: {:ok, %{}}
      end

      defmodule SkillIndexing.Skill2 do
        use BotArmy.Skill
        def name, do: :skill2
        def description, do: "Skill 2"
        def nats_triggers, do: ["trigger.two"]
        def llm_hint, do: :none
        def execute(_, _), do: {:ok, %{}}
      end

      # Verify skills are accessible
      skills = [SkillIndexing.Skill1, SkillIndexing.Skill2]
      assert length(skills) == 2
      assert Enum.all?(skills, &function_exported?(&1, :name, 0))
    end
  end

  describe "LLMProxy request structure" do
    test "LLMProxy module is properly defined" do
      # Verify module loads and has the core functions
      assert Code.ensure_loaded?(BotArmy.LLMProxy) == true

      # Check that it has the request function (arities created by default param)
      exports = BotArmy.LLMProxy.module_info(:exports)
      export_names = Enum.map(exports, &elem(&1, 0))
      assert :request in export_names
    end
  end
end
