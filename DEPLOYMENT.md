# Deployment

`bot_army_core` is a library, not a standalone service. It's included as a dependency in your bot's `mix.exs`.

## Installation

Add to your bot's `mix.exs`:

```elixir
def deps do
  [
    {:bot_army_core, "~> 0.1"}
  ]
end
```

## Configuration

Configure handlers and stores in your bot's `config/config.exs`:

```elixir
# Define which handler modules to load
config :my_bot, :handlers, [
  MyBot.Handlers.TaskHandler,
  MyBot.Handlers.NotificationHandler
]

# Configure stores
config :my_bot, :stores, [
  task_store: MyBot.Stores.TaskStore,
  notification_store: MyBot.Stores.NotificationStore
]
```

## Testing Configuration

For test environment:

```elixir
config :my_bot, :env, :test

# Use in-memory storage for tests
config :my_bot, :repo, BotArmyTest.Repo
```

## Troubleshooting

### Handlers not being called

**Symptom:** Handler modules are defined but functions never execute

**Cause:** Handlers not registered in config, or NATS router not subscribed

**Solution:**
1. Verify handlers in `config/config.exs`
2. Check NATS router is subscribing to correct subjects
3. Verify NATS connection is active

### Store persistence not working

**Symptom:** Data is lost after bot restart

**Cause:** Store not persisting to Ecto on updates

**Solution:**
1. Verify Ecto schema exists for your data
2. Check store implementation calls `Repo.insert_or_update!` before acknowledging
3. Monitor database logs for errors
