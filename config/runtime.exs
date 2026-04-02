import Config

# Runtime configuration — evaluated when the app starts, not at compile time
# This allows environment variables set by launchd/Salt to be read properly

# GraphDB (Apache AGE) Configuration at runtime
# Priority: GRAPHDB_* (set by Salt) > defaults
config :bot_army_core, BotArmyCore.GraphRepo,
  hostname: System.get_env("GRAPHDB_HOST", "localhost"),
  port: String.to_integer(System.get_env("GRAPHDB_PORT", "30002")),
  username: System.get_env("GRAPHDB_USER", "postgres"),
  password: System.get_env("GRAPHDB_PASSWORD", "postgres"),
  database: System.get_env("GRAPHDB_NAME", "ergon_graphs"),
  pool_size: 5

# Graph database enabled if explicitly set to "true" by bot config
# Bots opt in via: config :bot_army_core, :graph_enabled, true
# In runtime, we respect that config (defaults to false)
graph_enabled = System.get_env("GRAPH_ENABLED", "false") == "true"
config :bot_army_core, :graph_enabled, graph_enabled
