# Architecture

## Overview

`bot_army_core` provides foundational patterns and utilities for all Bot Army bots:

- **Handler Pattern**: Callback modules for processing domain-specific events
- **Store Pattern**: In-memory caching with persistent backing store (Ecto)
- **Supervisor Utilities**: Common supervision tree patterns
- **Testing Helpers**: Mocks and fixtures for bot testing

## Design Goals

1. **Consistency**: All bots follow the same patterns (handlers, stores, supervisors)
2. **Testability**: Patterns designed for easy mocking and unit testing
3. **Simplicity**: Minimal abstraction, maximum explicitness
4. **Reusability**: Common utilities extracted and shared

## Core Patterns

### Handler Pattern

Handlers are callback modules that respond to events:

```elixir
defmodule MyBot.Handlers.TaskHandler do
  def handle_task_created(task) do
    # Process the event
    :ok
  end
end
```

**Why this pattern:**
- Events (NATS messages) map directly to handler functions
- Type-safe, explicit contract
- Easy to test: `TaskHandler.handle_task_created(test_task)`

### Store Pattern

Stores manage state (in-memory cache + persistent backing):

```elixir
defmodule MyBot.Stores.TaskStore do
  def list_all, do: GenServer.call(__MODULE__, :list_all)
  def get(id), do: GenServer.call(__MODULE__, {:get, id})
  def put(id, task), do: GenServer.cast(__MODULE__, {:put, id, task})
end
```

**Lifecycle:**
1. Bot starts: Store loads all data from Ecto on init
2. Bot runs: Cache in-memory map (fast reads)
3. Bot updates: Persist to Ecto before acknowledging update
4. Bot crashes: Restart, reload from Ecto (no data loss)

### Supervisor Pattern

Common supervision patterns for bot process hierarchies:

```elixir
defmodule MyBot.Supervisor do
  def start_link(opts) do
    Supervisor.start_link([
      {MyBot.Stores.TaskStore, []},
      {MyBot.Handlers.Router, []},
      # ... other children
    ], opts)
  end
end
```

## Testing Patterns

### Unit Testing (Fast, No NATS)

Test handler logic directly:

```elixir
test "handler processes task correctly" do
  task = %Task{id: 1, title: "Test"}
  assert :ok = TaskHandler.handle_task_created(task)
end
```

### Integration Testing (With NATS)

Tag with `@tag :integration` to run with real NATS:

```elixir
@tag :integration
test "bot receives task from NATS" do
  # Publish to NATS, verify response
end
```

## Module Organization

```
lib/my_bot/
├── application.ex        # App supervision tree
├── handlers/
│   ├── task_handler.ex
│   ├── notification_handler.ex
│   └── ...
├── stores/
│   ├── task_store.ex
│   └── ...
├── schemas/              # Ecto schemas
│   ├── task.ex
│   └── ...
└── nats/
    └── consumer.ex       # NATS subscription setup
```

## Error Handling

- **Handlers**: Return `:ok` or `{:error, reason}`. Errors are logged but don't crash the bot.
- **Stores**: Return `{:ok, data}` or `{:error, reason}`. Always available (fallback to empty cache on error).
- **Telemetry**: All operations emit events for monitoring and debugging.

## Performance

- **Handlers**: Synchronous, sub-millisecond execution
- **Stores**: In-memory cache, O(1) lookups for common operations
- **Persistence**: Batch writes to database (configurable)
