# Quick Start

Get started using bot_army_core patterns in 10 minutes.

## Installation

Add to `mix.exs`:

```elixir
def deps do
  [{:bot_army_core, "~> 0.1"}]
end
```

Run `mix deps.get`.

## Handler Pattern

Create a handler module:

```elixir
# lib/my_bot/handlers/task_handler.ex
defmodule MyBot.Handlers.TaskHandler do
  @moduledoc "Handles task-related events"
  
  def handle_task_created(task) do
    IO.puts("New task: #{task.title}")
    :ok
  end
  
  def handle_task_updated(task) do
    IO.puts("Task updated: #{task.title}")
    :ok
  end
end
```

To call it:

```elixir
MyBot.Handlers.TaskHandler.handle_task_created(%Task{title: "My task"})
```

## Store Pattern

Create a store (in-memory cache with Ecto backing):

```elixir
# lib/my_bot/stores/task_store.ex
defmodule MyBot.Stores.TaskStore do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end
  
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end
  
  def put(id, task) do
    GenServer.cast(__MODULE__, {:put, id, task})
  end
  
  @impl true
  def init(_opts) do
    # Load all tasks from database on startup
    tasks = MyBot.Repo.all(MyBot.Schemas.Task)
    cache = Map.new(tasks, &{&1.id, &1})
    {:ok, cache}
  end
  
  @impl true
  def handle_call(:list_all, _from, cache) do
    {:reply, Map.values(cache), cache}
  end
  
  def handle_call({:get, id}, _from, cache) do
    {:reply, Map.get(cache, id), cache}
  end
  
  @impl true
  def handle_cast({:put, id, task}, cache) do
    # Persist to database
    MyBot.Repo.insert_or_update!(task)
    # Update cache
    new_cache = Map.put(cache, id, task)
    {:noreply, new_cache}
  end
end
```

To use it:

```elixir
# List all
MyBot.Stores.TaskStore.list_all()

# Get one
MyBot.Stores.TaskStore.get(123)

# Update (persists to DB)
MyBot.Stores.TaskStore.put(123, %Task{id: 123, title: "Updated"})
```

## Testing

### Unit Test (No Database)

```elixir
test "handler processes task" do
  task = %Task{id: 1, title: "Test"}
  assert :ok = TaskHandler.handle_task_created(task)
end
```

### Integration Test (With Database)

```elixir
@tag :integration
test "store persists task" do
  {:ok, pid} = TaskStore.start_link([])
  
  task = %Task{id: 1, title: "Test"}
  :ok = TaskStore.put(1, task)
  
  assert TaskStore.get(1) == task
  
  GenServer.stop(pid)
end
```

## Next Steps

- Read [ARCHITECTURE.md](../ARCHITECTURE.md) for detailed pattern explanations
- Check [API_REFERENCE.md](API_REFERENCE.md) for all utilities
- See [EXAMPLES.md](EXAMPLES.md) for real-world examples
