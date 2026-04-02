defmodule BotArmy.DefaultPersonality do
  @moduledoc """
  Default personality for bots using BotArmy.GenBot.

  Provides fallback personality configuration when a bot doesn't specify
  its own personality module.

  Can be overridden per-bot via:

      use BotArmy.GenBot, personality: MyBot.Personality, ...
  """

  @doc """
  Returns the default personality configuration.

  ## Returns

  A map with personality settings:
  - `:system_prompt` — Default system message for the bot
  - `:name` — Name to use in responses
  - `:symbol` — Symbol/emoji to represent the bot
  """
  def config do
    %{
      system_prompt: "You are a helpful AI assistant.",
      name: "Bot",
      symbol: "◈"
    }
  end
end
