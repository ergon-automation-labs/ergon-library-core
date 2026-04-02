defmodule BotArmy.Graph do
  @moduledoc """
  Cypher query helpers for Apache AGE.

  Provides a simple wrapper around the AGE (Apache AGE) graph database
  running on PostgreSQL. Queries are executed via BotArmyCore.GraphRepo.

  ## Setup

  Before using the graph functions, you must:

  1. Enable graph support in your bot config:

      config :bot_army_core, :graph_enabled, true

  2. One-time setup in the graph database:

      psql -h localhost -p 30002 -U postgres -d ergon_graphs
      CREATE EXTENSION IF NOT EXISTS age;
      SELECT create_graph('knowledge');

  After that, all graph functions operate on the 'knowledge' graph.

  ## Examples

      # Create/update nodes
      BotArmy.Graph.upsert_nodes([
        %{id: "alice", type: "person", name: "Alice", properties: %{email: "alice@example.com"}},
        %{id: "acme", type: "company", name: "Acme Corp", properties: %{industry: "tech"}}
      ])

      # Create relationships
      BotArmy.Graph.upsert_edges([
        %{from_id: "alice", to_id: "acme", type: "WORKS_AT", properties: %{since: 2024}}
      ])

      # Execute arbitrary Cypher
      BotArmy.Graph.query("MATCH (n:person) RETURN n LIMIT 10")
  """

  require Logger

  @graph_name "knowledge"

  @doc """
  Execute a raw Cypher query.

  The query is wrapped in the AGE SQL format and executed against
  the 'knowledge' graph.

  ## Arguments

  - `cypher` — Cypher query string

  ## Returns

  - `{:ok, results}` — List of results from the query
  - `{:error, reason}` — Database error

  ## Example

      {:ok, results} = BotArmy.Graph.query("MATCH (n) RETURN n LIMIT 5")
  """
  def query(cypher) when is_binary(cypher) do
    try do
      sanitized = sanitize(cypher)

      sql =
        "SELECT * FROM cypher('#{@graph_name}', $$ #{sanitized} $$) AS (result agtype)"

      result = BotArmyCore.GraphRepo.query!(sql, [])
      {:ok, result}
    rescue
      e ->
        Logger.error("[Graph] Query failed", query: cypher, error: inspect(e))
        {:error, :query_failed}
    end
  end

  @doc """
  Upsert nodes into the graph.

  Creates or updates nodes with the given properties. Uses Cypher MERGE
  to create-or-update by ID.

  ## Arguments

  - `nodes` — List of node maps with:
    - `:id` — Unique identifier
    - `:type` — Node label (e.g., 'person', 'company')
    - `:name` — Display name
    - `:properties` — Map of additional properties (optional)

  ## Returns

  - `{:ok, count}` — Number of nodes created/updated
  - `{:error, reason}` — Database error

  ## Example

      BotArmy.Graph.upsert_nodes([
        %{
          id: "bob-123",
          type: "person",
          name: "Bob Smith",
          properties: %{email: "bob@example.com", role: "engineer"}
        }
      ])
  """
  def upsert_nodes(nodes) when is_list(nodes) do
    try do
      count =
        Enum.reduce(nodes, 0, fn node, acc ->
          id = Map.fetch!(node, :id)
          type = Map.fetch!(node, :type)
          name = Map.fetch!(node, :name)
          properties = Map.get(node, :properties, %{})

          # Build Cypher for this node
          cypher =
            "MERGE (n:#{escape_label(type)} {id: '#{escape_string(id)}'}) " <>
              "SET n.name = '#{escape_string(name)}', " <>
              "n.updated_at = timestamp(), " <>
              "n.properties = #{format_properties(properties)}"

          query(cypher)
          acc + 1
        end)

      {:ok, count}
    rescue
      e ->
        Logger.error("[Graph] Upsert nodes failed", error: inspect(e))
        {:error, :upsert_failed}
    end
  end

  @doc """
  Upsert edges (relationships) into the graph.

  Creates or updates relationships between nodes.

  ## Arguments

  - `edges` — List of edge maps with:
    - `:from_id` — Source node ID
    - `:to_id` — Target node ID
    - `:type` — Relationship type (e.g., 'MANAGES', 'WORKS_AT')
    - `:properties` — Map of additional properties (optional)

  ## Returns

  - `{:ok, count}` — Number of edges created/updated
  - `{:error, reason}` — Database error

  ## Example

      BotArmy.Graph.upsert_edges([
        %{
          from_id: "alice-123",
          to_id: "acme-456",
          type: "WORKS_AT",
          properties: %{since: 2024, role: "engineer"}
        }
      ])
  """
  def upsert_edges(edges) when is_list(edges) do
    try do
      count =
        Enum.reduce(edges, 0, fn edge, acc ->
          from_id = Map.fetch!(edge, :from_id)
          to_id = Map.fetch!(edge, :to_id)
          type = Map.fetch!(edge, :type)
          properties = Map.get(edge, :properties, %{})

          # Build Cypher for this edge
          cypher =
            "MATCH (from {id: '#{escape_string(from_id)}'}) " <>
              "MATCH (to {id: '#{escape_string(to_id)}'}) " <>
              "MERGE (from)-[r:#{escape_label(type)}]->(to) " <>
              "SET r.updated_at = timestamp(), " <>
              "r.properties = #{format_properties(properties)}"

          query(cypher)
          acc + 1
        end)

      {:ok, count}
    rescue
      e ->
        Logger.error("[Graph] Upsert edges failed", error: inspect(e))
        {:error, :upsert_failed}
    end
  end

  # Private helpers

  defp sanitize(cypher) when is_binary(cypher) do
    cypher
    |> String.replace("$$", "")
    |> String.replace("'", "''")
  end

  defp escape_string(s) when is_binary(s) do
    String.replace(s, "'", "''")
  end

  defp escape_label(label) when is_binary(label) do
    String.replace(label, ~r/[^a-zA-Z0-9_]/, "")
  end

  defp format_properties(map) when is_map(map) do
    map
    |> Jason.encode!()
    |> escape_string()
  end
end
