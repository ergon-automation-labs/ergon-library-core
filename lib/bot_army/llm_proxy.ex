defmodule BotArmy.LLMProxy do
  @moduledoc """
  Proxy for calling the LLM bot from skills via NATS.

  Skills don't call the LLM directly. Instead, they publish a request
  to the LLM bot via NATS and wait for the reply.

  ## Usage

      # In a skill's execute/2 function:
      {:ok, completion} = ctx.llm.request(
        "Summarize this text: " <> text,
        hint: :fast
      )

  The LLMProxy handles:
  1. Generating a unique prompt_id
  2. Subscribing to the completion reply subject
  3. Publishing to llm.prompt.submit
  4. Waiting for a reply matching the prompt_id
  5. Returning the completion text

  ## Returns

  - `{:ok, completion_text}` on success
  - `{:error, :timeout}` if no reply within timeout
  - `{:error, reason}` on other failures
  """

  require Logger

  @default_timeout 15_000

  @doc """
  Request LLM completion for a prompt.

  Publishes a prompt to the LLM bot and waits for the response.
  This runs in the calling process (typically a Task).

  ## Arguments

  - `prompt` — Text prompt to send to LLM
  - `opts` — Options:
    - `:hint` — LLM routing hint (:fast, :quality, :research, :none)
    - `:timeout` — Timeout in milliseconds (default: 15000)

  ## Returns

  - `{:ok, completion}` — LLM response text
  - `{:error, :timeout}` — No response within timeout
  - `{:error, reason}` — Other errors

  ## Example

      {:ok, summary} = BotArmy.LLMProxy.request(
        "Summarize: " <> text,
        hint: :fast,
        timeout: 10_000
      )
  """
  def request(prompt, opts \\ []) when is_binary(prompt) do
    hint = Keyword.get(opts, :hint, :none)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    try do
      prompt_id = UUID.uuid4()
      reply_subject = "events.llm.completion.core.skill_llm_request"

      # Subscribe to replies before publishing (avoid race)
      with {:ok, _} <- BotArmyCore.NATS.subscribe(reply_subject) do
        # Publish request to LLM bot
        publish_llm_request(prompt, prompt_id, hint)

        # Wait for reply
        wait_for_reply(prompt_id, timeout)
      end
    rescue
      e ->
        Logger.error("[LLMProxy] Request failed", prompt: prompt, error: inspect(e))
        {:error, :request_failed}
    end
  end

  # Private helpers

  defp publish_llm_request(prompt, prompt_id, hint) do
    envelope = %{
      "event" => "llm.prompt.submit",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_core",
      "source_node" => node() |> Atom.to_string(),
      "triggered_by" => "skill.execution",
      "schema_version" => "1.0",
      "source_metadata" => %{"source_domain" => "skill_llm_request"},
      "payload" => %{
        "text" => prompt,
        "prompt_id" => prompt_id,
        "model" => hint_to_model(hint)
      }
    }

    BotArmyCore.NATS.publish("llm.prompt.submit", envelope)
  end

  defp wait_for_reply(prompt_id, timeout) do
    receive do
      {:msg, %{topic: _topic, body: body}} ->
        try do
          reply = Jason.decode!(body)

          # Check if this reply matches our prompt_id
          if reply["payload"]["original_prompt_id"] == prompt_id do
            case reply["payload"]["completion"] do
              completion when is_binary(completion) ->
                {:ok, completion}

              nil ->
                {:error, :no_completion}

              _ ->
                {:error, :invalid_completion}
            end
          else
            # Not our reply, wait for another
            wait_for_reply(prompt_id, timeout)
          end
        rescue
          e ->
            Logger.error("[LLMProxy] Failed to parse reply", error: inspect(e))
            {:error, :parse_failed}
        end
    after
      timeout ->
        Logger.warning("[LLMProxy] Request timeout", prompt_id: prompt_id)
        {:error, :timeout}
    end
  end

  defp hint_to_model(:fast), do: "auto"
  defp hint_to_model(:quality), do: "auto"
  defp hint_to_model(:research), do: "auto"
  defp hint_to_model(:none), do: "auto"
end
