defmodule BotArmy.Skills.ExtractEntities do
  @moduledoc """
  Skill for extracting entities and relationships from text.

  Uses LLM to identify people, companies, projects, tasks, and places
  from unstructured text, then stores them in the knowledge graph.

  This is the foundational skill for building a knowledge graph from
  bot conversations and interactions.

  ## Input

  ```elixir
  %{"content" => "Alice works at Acme Corp as an engineer"}
  ```

  ## Output

  ```elixir
  {:ok, %{entities_extracted: 2, edges_created: 1}}
  ```

  ## Extracted Entities

  ### Node Types

  - `person` — Individual person
  - `company` — Business or organization
  - `project` — Project or initiative
  - `task` — Work item or task
  - `place` — Location or place

  ### Relationship Types

  - `WORKS_AT` — Person works at company
  - `MANAGES` — Person manages another person or project
  - `RELATED_TO` — Generic relationship
  - `ASSIGNED_TO` — Task assigned to person

  ## LLM Prompt

  The skill asks the LLM to extract structured JSON with nodes and edges.
  """

  use BotArmy.Skill

  require Logger

  @impl true
  def name, do: :extract_entities

  @impl true
  def description do
    "Extracts entities (people, companies, projects) and relationships from text, " <>
      "stores in knowledge graph"
  end

  @impl true
  def nats_triggers do
    [
      "generalist.command.extract",
      "email.triage.message.classified"
    ]
  end

  @impl true
  def llm_hint, do: :fast

  @impl true
  def validate(%{"content" => content}) when is_binary(content) and byte_size(content) > 0 do
    :ok
  end

  def validate(_) do
    {:error, "content field required and must be non-empty string"}
  end

  @impl true
  def execute(%{"content" => content}, ctx) do
    try do
      with {:ok, raw} <- ctx.llm.request(extraction_prompt(content), hint: :fast),
           {:ok, entities} <- Jason.decode(raw) do
        nodes = entities["nodes"] || []
        edges = entities["edges"] || []

        # Store in knowledge graph
        case upsert_graph(nodes, edges) do
          {:ok, _} ->
            {:ok,
             %{
               entities_extracted: length(nodes),
               relationships_created: length(edges)
             }}

          {:error, reason} ->
            Logger.error("[ExtractEntities] Failed to store in graph: error=#{inspect(reason)}")
            {:error, {:graph_error, reason}}
        end
      end
    rescue
      e ->
        Logger.error("[ExtractEntities] Execution failed: error=#{inspect(e)}")
        {:error, :execution_failed}
    end
  end

  # Private helpers

  defp extraction_prompt(content) do
    """
    Extract entities and relationships from the following text.
    Return a JSON object with two arrays: "nodes" and "edges".

    Nodes should have: id, type (person|company|project|task|place), name, properties {}
    Edges should have: from_id, to_id, type (WORKS_AT|MANAGES|RELATED_TO|ASSIGNED_TO), properties {}

    Text to analyze:
    #{content}

    Respond with valid JSON only (no markdown, no explanation).
    """
  end

  defp upsert_graph(nodes, edges) do
    try do
      # Normalize nodes
      normalized_nodes =
        Enum.map(nodes, fn node ->
          %{
            id: to_string(node["id"] || ""),
            type: to_string(node["type"] || "unknown"),
            name: to_string(node["name"] || ""),
            properties: Map.get(node, "properties", %{})
          }
        end)

      # Normalize edges
      normalized_edges =
        Enum.map(edges, fn edge ->
          %{
            from_id: to_string(edge["from_id"] || ""),
            to_id: to_string(edge["to_id"] || ""),
            type: to_string(edge["type"] || "RELATED_TO"),
            properties: Map.get(edge, "properties", %{})
          }
        end)

      # Upsert to graph
      with {:ok, _} <- BotArmy.Graph.upsert_nodes(normalized_nodes),
           {:ok, _} <- BotArmy.Graph.upsert_edges(normalized_edges) do
        {:ok, %{nodes: length(normalized_nodes), edges: length(normalized_edges)}}
      end
    rescue
      e ->
        Logger.error("[ExtractEntities] Graph upsert failed: error=#{inspect(e)}")
        {:error, :graph_upsert_failed}
    end
  end
end
