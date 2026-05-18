# API Reference

## Handler Callback Pattern

Standard interface for all handlers:

```elixir
defmodule BotArmyCore.Handler do
  @callback handle_event(event :: map()) :: :ok | {:error, term()}
end
```

## Store GenServer Pattern

Standard store interface:

```elixir
defmodule BotArmyCore.Store do
  @callback list_all() :: [term()]
  @callback get(id :: any()) :: term() | nil
  @callback put(id :: any(), item :: term()) :: :ok | {:error, term()}
  @callback delete(id :: any()) :: :ok | {:error, term()}
end
```

## Supervisor Utilities

### `BotArmyCore.Supervisor.start_link(children, options)`

Start a supervision tree for a bot.

```elixir
Supervisor.start_link([
  {Store1, []},
  {Store2, []},
  {Handler, []}
], strategy: :one_for_one, name: MyBot.Supervisor)
```

## Testing Helpers

### `BotArmyCore.Test.assert_handler_ok(handler, function, args)`

Assert a handler function executes successfully.

```elixir
BotArmyCore.Test.assert_handler_ok(TaskHandler, :handle_task_created, [task])
```

### `BotArmyCore.Test.mock_store(module, implementations)`

Create a mock store for testing.

```elixir
mock = BotArmyCore.Test.mock_store(TaskStore, list_all: [task1, task2])
assert TaskStore.list_all() == [task1, task2]
```
