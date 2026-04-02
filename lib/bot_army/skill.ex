defmodule BotArmy.Skill do
  @moduledoc """
  Behaviour for BotArmy skills.

  Skills are modular, reusable pieces of functionality that can be triggered
  via NATS messages and invoked by the GenBot harness.

  ## Required Callbacks

  - `name/0` — Atom name for the skill (e.g., `:summarize`)
  - `description/0` — Human-readable description of what the skill does
  - `nats_triggers/0` — List of NATS subjects that trigger this skill
  - `llm_hint/0` — Hint for LLM routing (`:fast`, `:quality`, `:research`, or `:none`)
  - `execute/2` — Main skill logic (input, context) -> {:ok, result} or {:error, reason}

  ## Optional Callbacks

  - `validate/1` — Validate input before execution (defaults to accepting all)

  ## Context Injection

  Skills receive a context map with:

  ```elixir
  %{
    bot_id: :atom,              # The bot running the skill
    personality: map(),         # Personality config from the bot
    context: map(),             # Current context from Context Broker
    llm: BotArmy.LLMProxy       # LLM proxy module (call via ctx.llm.request/2)
  }
  ```

  ## Example

      defmodule MyBot.Skills.Summarize do
        use BotArmy.Skill

        def name, do: :summarize
        def description, do: "Summarizes text using LLM"
        def nats_triggers, do: ["mybot.command.summarize"]
        def llm_hint, do: :fast

        def execute(%{"text" => text}, ctx) do
          with {:ok, summary} <- ctx.llm.request("Summarize: " <> text, hint: llm_hint()) do
            {:ok, %{summary: summary}}
          end
        end

        def validate(%{"text" => t}) when is_binary(t) and byte_size(t) > 0, do: :ok
        def validate(_), do: {:error, "text field required"}
      end
  """

  @type input :: map()
  @type context :: %{
    bot_id: atom(),
    personality: map(),
    context: map(),
    llm: module()
  }
  @type output :: {:ok, map()} | {:error, term()}

  @callback name() :: atom()
  @callback description() :: String.t()
  @callback nats_triggers() :: [String.t()]
  @callback llm_hint() :: :fast | :quality | :research | :none
  @callback execute(input(), context()) :: output()
  @callback validate(input()) :: :ok | {:error, String.t()}

  @optional_callbacks validate: 1

  @doc """
  Helper macro for implementing a skill.

  Provides a default `validate/1` implementation that accepts all input.
  Override by defining your own `validate/1` function.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour BotArmy.Skill

      @doc false
      def validate(_input), do: :ok

      defoverridable validate: 1
    end
  end
end
