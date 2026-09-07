defmodule BotArmy.Skill do
  @moduledoc """
  Base module for bot skills. Provides the behavior and macro for skill implementation.
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour BotArmy.Skill
      import BotArmy.Skill
    end
  end

  @callback name() :: atom()
  @callback description() :: String.t()
  @callback nats_triggers() :: [String.t()]
  @callback llm_hint() :: :fast | :deep
  @callback validate(map()) :: :ok | {:error, String.t()}
  @callback execute(map(), map()) :: {:ok, any()} | {:error, any()}
end
