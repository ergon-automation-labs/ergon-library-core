import Config

# Logger with correlation_id support
config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: "[$time] [$level] $message\n",
  metadata: [:correlation_id, :subject, :reason, :error]

# Ecto repo configuration (compile-time)
# Runtime config for GraphRepo connection settings is in config/runtime.exs
config :bot_army_library_core, ecto_repos: [BotArmyCore.GraphRepo]

# config/{env}.exs (test.exs, dev.exs, etc.) was never imported, so any
# override it defined (most commonly a *_test database name) was dead code —
# every mix invocation used the settings above unmodified, regardless of
# MIX_ENV. Guarded by File.exists? since not every env has its own file here.
env_config = "#{config_env()}.exs"

if File.exists?(Path.join(__DIR__, env_config)) do
  import_config env_config
end
