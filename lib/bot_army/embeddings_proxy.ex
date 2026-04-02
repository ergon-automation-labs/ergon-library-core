defmodule BotArmy.EmbeddingsProxy do
  @moduledoc """
  Proxy for requesting text embeddings from the LLM bot via NATS.

  Skills don't request embeddings directly. Instead, they publish a request
  to the LLM bot via NATS and wait for the embedding vector reply.

  ## Usage

      # In a skill's execute/2 function:
      {:ok, embedding} = ctx.embeddings.request(
        "Extract entities from: " <> text,
        model: :nomic
      )

  The EmbeddingsProxy handles:
  1. Generating a unique embedding_id for correlation
  2. Subscribing to the embedding reply subject
  3. Publishing to llm.embed.request
  4. Waiting for a reply matching the embedding_id
  5. Returning the embedding vector

  ## Returns

  - `{:ok, embedding_vector}` on success (768-dimensional vector)
  - `{:error, :timeout}` if no reply within timeout
  - `{:error, reason}` on other failures

  ## Embedding Model

  Default model is `nomic-embed-text` (768-dimensional vectors).
  Suitable for semantic search, similarity scoring, and RAG applications.
  """

  require Logger

  @default_timeout 30_000

  @doc """
  Request text embedding from the LLM bot.

  Publishes an embedding request to the LLM bot and waits for the vector response.
  This runs in the calling process (typically a Task).

  ## Arguments

  - `text` — Text to embed
  - `opts` — Options:
    - `:model` — Embedding model (default: `:nomic`)
    - `:timeout` — Timeout in milliseconds (default: 30000)

  ## Returns

  - `{:ok, embedding_vector}` — 768-dimensional embedding vector
  - `{:error, :timeout}` — No response within timeout
  - `{:error, reason}` — Other errors

  ## Example

      {:ok, vector} = BotArmy.EmbeddingsProxy.request(
        "Learn about knowledge graphs",
        model: :nomic,
        timeout: 20_000
      )

      # vector is a list of 768 floats: [0.123, -0.456, ...]
  """
  def request(text, opts \\ []) when is_binary(text) do
    model = Keyword.get(opts, :model, :nomic)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    try do
      embedding_id = UUID.uuid4()
      reply_subject = "events.llm.embedding.created"

      # Subscribe to replies before publishing (avoid race)
      with {:ok, _} <- BotArmyCore.NATS.subscribe(reply_subject) do
        # Publish request to LLM bot
        publish_embedding_request(text, embedding_id, model)

        # Wait for reply
        wait_for_embedding(embedding_id, timeout)
      end
    rescue
      e ->
        Logger.error("[EmbeddingsProxy] Request failed", text: text, error: inspect(e))
        {:error, :request_failed}
    end
  end

  # Private helpers

  defp publish_embedding_request(text, embedding_id, model) do
    envelope = %{
      "event" => "llm.embed.request",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_core",
      "source_node" => node() |> Atom.to_string(),
      "triggered_by" => "skill.execution",
      "schema_version" => "1.0",
      "source_metadata" => %{"source_domain" => "skill_embedding_request"},
      "payload" => %{
        "text" => text,
        "embedding_id" => embedding_id,
        "model" => model_to_string(model),
        "card_id" => nil
      }
    }

    BotArmyCore.NATS.publish("llm.embed.request", envelope)
  end

  defp wait_for_embedding(embedding_id, timeout) do
    receive do
      {:msg, %{topic: _topic, body: body}} ->
        try do
          reply = Jason.decode!(body)

          # Check if this reply matches our embedding_id
          if reply["payload"]["embedding_id"] == embedding_id do
            case reply["payload"]["embedding"] do
              embedding when is_list(embedding) ->
                {:ok, embedding}

              nil ->
                {:error, :no_embedding}

              _ ->
                {:error, :invalid_embedding}
            end
          else
            # Not our reply, wait for another
            wait_for_embedding(embedding_id, timeout)
          end
        rescue
          e ->
            Logger.error("[EmbeddingsProxy] Failed to parse embedding reply",
              error: inspect(e)
            )

            {:error, :parse_failed}
        end
    after
      timeout ->
        Logger.warning("[EmbeddingsProxy] Request timeout", embedding_id: embedding_id)
        {:error, :timeout}
    end
  end

  defp model_to_string(:nomic), do: "nomic-embed-text"
  defp model_to_string(:openai), do: "text-embedding-3-small"
  defp model_to_string(model) when is_binary(model), do: model
  defp model_to_string(_), do: "nomic-embed-text"
end
