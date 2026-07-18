defmodule BotArmyLibraryCore.OutcomesEmitter do
  @moduledoc """
  Helper module for emitting outcomes.* events to NATS.

  All bots use this to standardize how they report:
  - Task completions and rejections
  - Decomposition quality and outcomes
  - Context mode transitions
  - Notification actions
  - Learning outcomes
  - System health signals

  Usage:
      BotArmyLibraryCore.OutcomesEmitter.emit_task_completed(
        task_id,
        %{
          "metric_name" => "completion_rate",
          "bot_name" => "gtd",
          "value" => 1.0,
          "priority" => "high",
          "project" => "project-123"
        }
      )
  """

  require Logger

  @doc """
  Emit a task completion event.
  """
  def emit_task_completed(task_id, metadata) do
    emit_event("outcomes.task.completed", %{
      "task_id" => task_id,
      "metric_name" => "task_completed",
      "bot_name" => Map.get(metadata, "bot_name", "unknown"),
      "value" => 1.0,
      "metadata" => Map.drop(metadata, ["bot_name"])
    })
  end

  @doc """
  Emit a task rejection event.
  """
  def emit_task_rejected(task_id, metadata) do
    emit_event("outcomes.task.rejected", %{
      "task_id" => task_id,
      "metric_name" => "task_rejected",
      "bot_name" => Map.get(metadata, "bot_name", "unknown"),
      "value" => 1.0,
      "metadata" => Map.drop(metadata, ["bot_name"])
    })
  end

  @doc """
  Emit a decomposition completion event with quality metric.
  """
  def emit_decomposition_completed(decomp_id, quality_score, metadata) do
    emit_event("outcomes.decomposition.completed", %{
      "decomposition_id" => decomp_id,
      "metric_name" => "decomposition_quality",
      "bot_name" => Map.get(metadata, "bot_name", "llm"),
      "value" => quality_score,
      "metadata" => Map.drop(metadata, ["bot_name"])
    })
  end

  @doc """
  Emit a mode transition event.
  """
  def emit_mode_transition(from_mode, to_mode, confidence) do
    emit_event("outcomes.context.mode_transition", %{
      "metric_name" => "mode_prediction_accuracy",
      "bot_name" => "context_broker",
      "value" => confidence,
      "metadata" => %{
        "mode_from" => from_mode,
        "mode_to" => to_mode
      }
    })
  end

  @doc """
  Emit a notification action event.
  """
  def emit_notification_action(notification_id, action, metadata) do
    subject =
      case action do
        :dismissed -> "outcomes.notification.dismissed"
        :acted -> "outcomes.notification.acted"
        _ -> "outcomes.notification.other"
      end

    emit_event(subject, %{
      "notification_id" => notification_id,
      "metric_name" => "notification_efficacy",
      "bot_name" => Map.get(metadata, "bot_name", "notification_router"),
      "value" => if(action == :acted, do: 1.0, else: 0.0),
      "metadata" => Map.drop(metadata, ["bot_name"])
    })
  end

  @doc """
  Emit a learning outcome event.
  """
  def emit_learning_outcome(category, bot_name, accuracy) do
    emit_event("outcomes.learning.#{bot_name}", %{
      "metric_name" => "learning_outcome_accuracy",
      "bot_name" => bot_name,
      "value" => accuracy,
      "metadata" => %{
        "category" => category
      }
    })
  end

  @doc """
  Emit a bridge responder latency event.
  """
  def emit_responder_latency(responder_name, latency_ms) do
    emit_event("outcomes.bridge.responder_latency", %{
      "metric_name" => "responder_latency_p95",
      "bot_name" => "bridge",
      "value" => latency_ms,
      "metadata" => %{
        "responder" => responder_name
      }
    })
  end

  @doc """
  Emit a system health signal.
  """
  def emit_health(bot_name, status) do
    emit_event("system.health.#{bot_name}", %{
      "metric_name" => "system_reliability",
      "bot_name" => bot_name,
      "value" => if(status == :healthy, do: 1.0, else: 0.0),
      "metadata" => %{
        "status" => status
      }
    })
  end

  # Private: emit the actual NATS event
  defp emit_event(subject, payload) do
    case encode_event(payload) do
      {:ok, json} ->
        try do
          case Gnat.pub(:nats_connection, subject, json) do
            :ok ->
              Logger.debug("Emitted outcomes event", subject: subject)

            {:error, reason} ->
              Logger.warning("Failed to emit outcomes event",
                subject: subject,
                reason: reason
              )
          end
        catch
          :exit, reason ->
            Logger.warning("NATS unavailable, outcomes event dropped",
              subject: subject,
              reason: inspect(reason)
            )
        end

      {:error, reason} ->
        Logger.warning("Failed to encode outcomes event",
          subject: subject,
          reason: reason
        )
    end
  end

  defp encode_event(payload) do
    Jason.encode(payload)
  end
end
