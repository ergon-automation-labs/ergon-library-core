# Examples

## Complete Handler Implementation

```elixir
defmodule MyBot.Handlers.TaskHandler do
  @moduledoc "Processes task-related events from NATS"
  
  require Logger
  
  def handle_task_created(task) do
    Logger.info("Task created: #{task.id}")
    
    # Could notify other systems, update cache, etc.
    case MyBot.Stores.TaskStore.put(task.id, task) do
      :ok ->
        :ok
      {:error, reason} ->
        Logger.error("Failed to store task: #{inspect(reason)}")
        {:error, :store_failure}
    end
  end
  
  def handle_task_updated(task) do
    Logger.info("Task updated: #{task.id}")
    MyBot.Stores.TaskStore.put(task.id, task)
  end
  
  def handle_task_deleted(task_id) do
    Logger.info("Task deleted: #{task_id}")
    MyBot.Stores.TaskStore.delete(task_id)
  end
end
```

## Complete Store Implementation

```elixir
defmodule MyBot.Stores.TaskStore do
  use GenServer
  require Logger
  
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
  
  def delete(id) do
    GenServer.cast(__MODULE__, {:delete, id})
  end
  
  @impl true
  def init(_opts) do
    Logger.info("TaskStore starting...")
    
    # Load all tasks from database
    tasks = MyBot.Repo.all(MyBot.Schemas.Task)
    cache = Map.new(tasks, &{&1.id, &1})
    
    Logger.info("TaskStore loaded #{map_size(cache)} tasks")
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
    # Persist to database first (fail-safe)
    case MyBot.Repo.insert_or_update(task) do
      {:ok, persisted_task} ->
        new_cache = Map.put(cache, id, persisted_task)
        {:noreply, new_cache}
      
      {:error, reason} ->
        Logger.error("Failed to persist task #{id}: #{inspect(reason)}")
        {:noreply, cache}
    end
  end
  
  def handle_cast({:delete, id}, cache) do
    case MyBot.Repo.delete(cache[id]) do
      {:ok, _} ->
        new_cache = Map.delete(cache, id)
        {:noreply, new_cache}
      
      {:error, reason} ->
        Logger.error("Failed to delete task #{id}: #{inspect(reason)}")
        {:noreply, cache}
    end
  end
end
```

## Testing Example

```elixir
defmodule MyBot.Handlers.TaskHandlerTest do
  use ExUnit.Case
  
  describe "handle_task_created/1" do
    test "stores task successfully" do
      task = %Task{id: 1, title: "Test task"}
      
      assert :ok = TaskHandler.handle_task_created(task)
    end
    
    test "returns error on store failure" do
      # This would require mocking the store
      # See test setup for store mock configuration
      task = %Task{id: 1, title: "Test task"}
      
      # Assuming store is mocked to fail
      # assert {:error, :store_failure} = TaskHandler.handle_task_created(task)
    end
  end
end
```
