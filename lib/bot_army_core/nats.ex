defmodule BotArmyCore.NATS do
  @moduledoc """
  NATS wrapper for BotArmy.

  This module provides a unified interface for:
  - Publishing messages to NATS
  - Subscribing to NATS subjects
  - Pattern matching NATS subject wildcards

  Wraps the lower-level BotArmyRuntime.NATS.* infrastructure.
  """

  require Logger

  @doc """
  Subscribe to a NATS subject or pattern.

  This uses the shared NATS connection from BotArmyRuntime.NATS.Connection
  and subscribes the current process to the given subject.

  ## Arguments

  - `subject`: NATS subject string (can include wildcards: `*` for single token, `>` for multi-token suffix)

  ## Returns

  - `{:ok, subscription_id}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> BotArmyCore.NATS.subscribe("bot.army.generalist.command.>")
      {:ok, 123}

      iex> BotArmyCore.NATS.subscribe("events.llm.response.*")
      {:ok, 456}
  """
  def subscribe(subject) when is_binary(subject) do
    with {:ok, conn} <- get_connection() do
      Gnat.sub(conn, self(), subject)
    end
  rescue
    e ->
      Logger.error("[NATS] Failed to subscribe", subject: subject, error: inspect(e))
      {:error, :subscribe_failed}
  end

  @doc """
  Publish a message to a NATS subject.

  This publishes JSON-encoded payload to the given subject via the shared connection.

  ## Arguments

  - `subject`: NATS subject string
  - `payload`: Map or term to be JSON-encoded and published

  ## Returns

  - `{:ok, subject}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> BotArmyCore.NATS.publish("events.gtd.task.created", %{"task_id" => "123"})
      {:ok, "events.gtd.task.created"}
  """
  def publish(subject, payload) when is_binary(subject) and is_map(payload) do
    BotArmyRuntime.NATS.Publisher.publish(subject, payload)
  rescue
    e ->
      Logger.error("[NATS] Failed to publish", subject: subject, error: inspect(e))
      {:error, :publish_failed}
  end

  @doc """
  Check if a NATS subject pattern matches a subject string.

  Implements NATS wildcard semantics:
  - `*` matches exactly one token (tokens separated by `.`)
  - `>` matches zero or more tokens from that point forward

  ## Arguments

  - `pattern`: NATS pattern string (may contain `*` or `>`)
  - `subject`: NATS subject string (no wildcards)

  ## Returns

  - `true` if the subject matches the pattern
  - `false` otherwise

  ## Examples

      iex> BotArmyCore.NATS.subject_matches?("a.b.c", "a.b.c")
      true

      iex> BotArmyCore.NATS.subject_matches?("a.*.c", "a.b.c")
      true

      iex> BotArmyCore.NATS.subject_matches?("a.>", "a.b.c.d")
      true

      iex> BotArmyCore.NATS.subject_matches?("a.b", "a.c")
      false
  """
  def subject_matches?(pattern, subject) when is_binary(pattern) and is_binary(subject) do
    pattern_tokens = String.split(pattern, ".")
    subject_tokens = String.split(subject, ".")

    match_tokens(pattern_tokens, subject_tokens)
  end

  # Private helpers

  defp get_connection do
    GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 1000)
  rescue
    _ -> {:error, :no_connection}
  end

  # Pattern matching for NATS subjects

  defp match_tokens([], []), do: true
  defp match_tokens([], _), do: false
  defp match_tokens([">"], _), do: true
  defp match_tokens([_pattern_token | _], []), do: false
  defp match_tokens(["*" | rest_pattern], [_subject_token | rest_subject]) do
    match_tokens(rest_pattern, rest_subject)
  end
  defp match_tokens([pattern_token | rest_pattern], [subject_token | rest_subject]) do
    if pattern_token == subject_token do
      match_tokens(rest_pattern, rest_subject)
    else
      false
    end
  end
end
