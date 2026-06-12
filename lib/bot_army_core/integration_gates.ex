defmodule BotArmyCore.IntegrationGates do
  @moduledoc """
  Central integration gating for all optional bot integrations.

  Each integration can be independently enabled/disabled via environment variables:
  - LLM_INTEGRATION_ENABLED (default: true)
  - BRIDGE_INTEGRATION_ENABLED (default: true)
  - PARA_INTEGRATION_ENABLED (default: true)
  - CONTEXT_INTEGRATION_ENABLED (default: true)
  - NOTIFICATION_INTEGRATION_ENABLED (default: true)
  - SYNAPSE_INTEGRATION_ENABLED (default: true)
  - DISPATCHER_INTEGRATION_ENABLED (default: true)

  Enables lean deployments: disable non-critical integrations for smaller core pack.
  """

  require Logger

  # LLM Integration
  def llm_enabled? do
    System.get_env("LLM_INTEGRATION_ENABLED", "true") != "false"
  end

  def llm_request(subject, payload, opts \\ []) do
    unless llm_enabled?() do
      Logger.debug("[IntegrationGates] LLM disabled, skipping #{subject}")
      {:error, :llm_integration_disabled}
    else
      BotArmyRuntime.NATS.Publisher.request(subject, payload, opts)
    end
  end

  def llm_publish(subject, payload) do
    unless llm_enabled?() do
      Logger.debug("[IntegrationGates] LLM disabled, skipping publish to #{subject}")
      :ok
    else
      BotArmyRuntime.NATS.Publisher.publish(subject, payload)
    end
  end

  # Bridge Integration (Claude Bridge)
  def bridge_enabled? do
    System.get_env("BRIDGE_INTEGRATION_ENABLED", "true") != "false"
  end

  def bridge_request(subject, payload, opts \\ []) do
    unless bridge_enabled?() do
      Logger.debug("[IntegrationGates] Bridge disabled, skipping #{subject}")
      {:error, :bridge_integration_disabled}
    else
      BotArmyRuntime.NATS.Publisher.request(subject, payload, opts)
    end
  end

  def bridge_publish(subject, payload) do
    unless bridge_enabled?() do
      Logger.debug("[IntegrationGates] Bridge disabled, skipping publish to #{subject}")
      :ok
    else
      BotArmyRuntime.NATS.Publisher.publish(subject, payload)
    end
  end

  # PARA Integration (Knowledge Persistence)
  def para_enabled? do
    System.get_env("PARA_INTEGRATION_ENABLED", "true") != "false"
  end

  def para_request(subject, payload, opts \\ []) do
    unless para_enabled?() do
      Logger.debug("[IntegrationGates] PARA disabled, skipping #{subject}")
      {:error, :para_integration_disabled}
    else
      BotArmyRuntime.NATS.Publisher.request(subject, payload, opts)
    end
  end

  def para_publish(subject, payload) do
    unless para_enabled?() do
      Logger.debug("[IntegrationGates] PARA disabled, skipping publish to #{subject}")
      :ok
    else
      BotArmyRuntime.NATS.Publisher.publish(subject, payload)
    end
  end

  # Context Broker Integration
  def context_enabled? do
    System.get_env("CONTEXT_INTEGRATION_ENABLED", "true") != "false"
  end

  def context_request(subject, payload, opts \\ []) do
    unless context_enabled?() do
      Logger.debug("[IntegrationGates] Context disabled, skipping #{subject}")
      {:error, :context_integration_disabled}
    else
      BotArmyRuntime.NATS.Publisher.request(subject, payload, opts)
    end
  end

  def context_publish(subject, payload) do
    unless context_enabled?() do
      Logger.debug("[IntegrationGates] Context disabled, skipping publish to #{subject}")
      :ok
    else
      BotArmyRuntime.NATS.Publisher.publish(subject, payload)
    end
  end

  # Notification Router Integration
  def notification_enabled? do
    System.get_env("NOTIFICATION_INTEGRATION_ENABLED", "true") != "false"
  end

  def notification_request(subject, payload, opts \\ []) do
    unless notification_enabled?() do
      Logger.debug("[IntegrationGates] Notifications disabled, skipping #{subject}")
      {:error, :notification_integration_disabled}
    else
      BotArmyRuntime.NATS.Publisher.request(subject, payload, opts)
    end
  end

  def notification_publish(subject, payload) do
    unless notification_enabled?() do
      Logger.debug("[IntegrationGates] Notifications disabled, skipping publish to #{subject}")
      :ok
    else
      BotArmyRuntime.NATS.Publisher.publish(subject, payload)
    end
  end

  # Synapse Integration (Discord/Social)
  def synapse_enabled? do
    System.get_env("SYNAPSE_INTEGRATION_ENABLED", "true") != "false"
  end

  def synapse_request(subject, payload, opts \\ []) do
    unless synapse_enabled?() do
      Logger.debug("[IntegrationGates] Synapse disabled, skipping #{subject}")
      {:error, :synapse_integration_disabled}
    else
      BotArmyRuntime.NATS.Publisher.request(subject, payload, opts)
    end
  end

  def synapse_publish(subject, payload) do
    unless synapse_enabled?() do
      Logger.debug("[IntegrationGates] Synapse disabled, skipping publish to #{subject}")
      :ok
    else
      BotArmyRuntime.NATS.Publisher.publish(subject, payload)
    end
  end

  # Dispatcher Integration (AI Orchestration)
  def dispatcher_enabled? do
    System.get_env("DISPATCHER_INTEGRATION_ENABLED", "true") != "false"
  end

  def dispatcher_request(subject, payload, opts \\ []) do
    unless dispatcher_enabled?() do
      Logger.debug("[IntegrationGates] Dispatcher disabled, skipping #{subject}")
      {:error, :dispatcher_integration_disabled}
    else
      BotArmyRuntime.NATS.Publisher.request(subject, payload, opts)
    end
  end

  def dispatcher_publish(subject, payload) do
    unless dispatcher_enabled?() do
      Logger.debug("[IntegrationGates] Dispatcher disabled, skipping publish to #{subject}")
      :ok
    else
      BotArmyRuntime.NATS.Publisher.publish(subject, payload)
    end
  end

  # Helper for Gnat-based calls (Discord, Synapse use Gnat directly)
  def gnat_request(conn, integration, subject, payload, opts) do
    enabled_fn = String.to_atom("#{integration}_enabled?")

    unless apply(__MODULE__, enabled_fn, []) do
      Logger.debug("[IntegrationGates] #{integration} disabled, skipping #{subject}")
      {:error, :"#{integration}_integration_disabled"}
    else
      Gnat.request(conn, subject, payload, opts)
    end
  end

  def gnat_pub(conn, integration, subject, payload) do
    enabled_fn = String.to_atom("#{integration}_enabled?")

    unless apply(__MODULE__, enabled_fn, []) do
      Logger.debug("[IntegrationGates] #{integration} disabled, skipping pub to #{subject}")
      :ok
    else
      Gnat.pub(conn, subject, payload)
    end
  end
end
