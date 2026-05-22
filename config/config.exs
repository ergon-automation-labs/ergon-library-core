import Config

# Ecto repo configuration (compile-time)
# Runtime config for GraphRepo connection settings is in config/runtime.exs
config :bot_army_library_core, ecto_repos: [BotArmyCore.GraphRepo]
