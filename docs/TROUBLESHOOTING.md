# Troubleshooting

## Handler Not Being Called

**Symptom:** Handler module exists but functions never execute

**Cause:**
- Handler not wired into bot's NATS subscription router
- Event doesn't match handler function name
- Handler module has syntax error

**Solution:**

1. Verify handler is registered in bot's main router/consumer
2. Check function name matches incoming event type
3. Run `mix compile` to catch syntax errors
4. Add debug logging to handler entry point

```elixir
def handle_event(event) do
  IO.inspect(event, label: "Received event")  # Debug
  # ... rest of handler
end
```

## Store Data Not Persisting

**Symptom:** Data appears in cache but is lost after bot restart

**Cause:**
- Store not calling `Repo.insert_or_update!` before returning
- Database insert/update failing silently
- Wrong database schema

**Solution:**

1. Verify store calls `Repo.insert_or_update!` in `handle_cast` before updating cache
2. Add error handling and logging:

```elixir
def handle_cast({:put, id, item}, cache) do
  case MyRepo.insert_or_update(item) do
    {:ok, persisted} ->
      Logger.info("Persisted item #{id}")
      {:noreply, Map.put(cache, id, persisted)}
    
    {:error, reason} ->
      Logger.error("Failed to persist: #{inspect(reason)}")
      {:noreply, cache}
  end
end
```

3. Check database logs for constraint violations
4. Verify Ecto schema matches data structure

## Store Crashes on Startup

**Symptom:** Bot fails to start with store error

**Cause:**
- Database connection not available
- Ecto schema error
- Data in database doesn't match schema

**Solution:**

1. Verify database is running and accessible
2. Check Ecto migrations are run: `mix ecto.migrate`
3. Run schema validation: `mix ecto.load`
4. Check schema definition matches data in database

## High Memory Usage in Store

**Symptom:** Memory grows unbounded as bot runs

**Cause:**
- Store cache growing without cleanup
- No delete operations, only puts
- Memory leak in cached objects

**Solution:**

1. Implement periodic cleanup:

```elixir
def handle_info(:cleanup, cache) do
  # Remove entries older than 1 hour
  Process.send_after(self(), :cleanup, 60 * 60 * 1000)
  {:noreply, cache}
end
```

2. Implement a max cache size:

```elixir
def handle_cast({:put, id, item}, cache) when map_size(cache) > 10000 do
  # Cache is too large, remove oldest
  {_id, _item} = cache |> Enum.min_by(fn {_, v} -> v.created_at end)
  # ... delete and update
end
```

3. Monitor with: `observer:start()` in IEx
