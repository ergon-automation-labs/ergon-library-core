defmodule BotArmyCore do
  @moduledoc """
  BotArmyCore is the shared message contract foundation and core library for the Bot Army ecosystem.

  It provides:
  - NATS message envelope handling (`BotArmyCore.NATS.Decoder`)
  - Standard error and acknowledgment response shapes
  - System health and alert definitions
  - Triggered_by audit value registry

  ## Schema References

  Core schemas are defined in the `bot_army_schemas` repository and deployed to:
  `/etc/bot_army/schemas/core/`

  The decoder reads these schemas at runtime to determine which message versions to accept.

  ## Usage

  See documentation in `lib/bot_army_core/nats/decoder.ex` for message handling.
  """

  @version "0.1.0"

  def version do
    @version
  end
end
