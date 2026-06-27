import Config

# Runtime configuration — evaluated when the app starts, not at compile time
# This allows environment variables set by launchd/Salt to be read properly

# GraphDB (Apache AGE) Configuration at runtime — dev fallback only
# Bots override this in their own runtime.exs with per-bot database names
# Priority: per-bot runtime.exs (GRAPHDB_NAME=ergon_graphdb_<bot>) > defaults
config :bot_army_library_core, BotArmyCore.GraphRepo,
  hostname: System.get_env("GRAPHDB_HOST", "localhost"),
  port: String.to_integer(System.get_env("GRAPHDB_PORT", "30002")),
  username: System.get_env("GRAPHDB_USER", "postgres"),
  password: System.get_env("GRAPHDB_PASSWORD", "postgres"),
  database: System.get_env("GRAPHDB_NAME", "ergon_graphs"),
  pool_size: System.get_env("BOT_POOL_SIZE", "15") |> String.to_integer(),

