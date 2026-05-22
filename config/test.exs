import Config

# Test environment configuration for bot_army_core

# Point to dev NATS (port 4223) instead of prod (4222)
config :bot_army_library_runtime, :nats,
  servers: [{"localhost", 4223}],
  ping_interval: 10_000,
  max_reconnect_attempts: 3,
  reconnect_delay_ms: 100

# Disable graph DB in tests (can be enabled per-test if needed)
config :bot_army_library_core, :graph_enabled, false
