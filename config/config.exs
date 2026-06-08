import Config

# Logger with correlation_id support
config :logger,
  level: :info,
  backends: [:console],
  default_formatter: {BotArmyRuntime.LoggerFormatter, []}

config :logger, :console,
  format: {BotArmyRuntime.LoggerFormatter, []},
  metadata: [:correlation_id]

# Ecto repo configuration (compile-time)
# Runtime config for GraphRepo connection settings is in config/runtime.exs
config :bot_army_library_core, ecto_repos: [BotArmyCore.GraphRepo]

