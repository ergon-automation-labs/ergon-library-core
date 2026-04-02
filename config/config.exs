import Config

# GraphDB (Apache AGE) Configuration
config :bot_army_core, BotArmyCore.GraphRepo,
  hostname: System.get_env("GRAPHDB_HOST", "localhost"),
  port: String.to_integer(System.get_env("GRAPHDB_PORT", "30002")),
  username: System.get_env("GRAPHDB_USER", "postgres"),
  password: System.get_env("GRAPHDB_PASSWORD", "postgres"),
  database: System.get_env("GRAPHDB_NAME", "ergon_graphs"),
  pool_size: 5

# Ecto repo configuration
config :bot_army_core, ecto_repos: [BotArmyCore.GraphRepo]

# Graph database is disabled by default — bots opt in via config :bot_army_core, :graph_enabled, true
config :bot_army_core, :graph_enabled, false
