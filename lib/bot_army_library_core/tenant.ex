defmodule BotArmyLibraryCore.Tenant do
  @moduledoc """
  Tenant identity for the multi-tenant Bot Army system.

  This module provides the core tenant utilities for the Bot Army ecosystem.

  ## Default Tenant

  The default tenant is a UUID for single-tenant deployments (Abby's personal system).
  SaaS tenants will have unique UUIDs assigned at provisioning time.

  ## Subject Prefixing

  Tenant-specific NATS subjects follow the pattern:
      tenant.<tenant_id>.events.*
      tenant.<tenant_id>.gtd.*
      etc.

  For more advanced tenant utilities, see `BotArmyLibraryRuntime.Tenant`.

  ## Deprecation Notes

  The `default_tenant_id/0` function returns a UUID. This is the standard tenant
  identifier for single-tenant deployments. SaaS tenants get their own UUIDs.
  """

  @default_tenant_id "00000000-0000-0000-0000-000000000001"
  @default_user_id "00000000-0000-0000-0000-000000000002"

  @doc """
  Returns the default tenant UUID.

  For single-tenant deployments (Abby's personal system), this returns a UUID
  that represents the default tenant. SaaS tenants will have unique UUIDs
  assigned at provisioning time.

  Returns: `"00000000-0000-0000-0000-000000000001"`
  """
  def default_tenant_id, do: @default_tenant_id

  @doc """
  Returns the default user UUID.

  For messages that don't specify a user_id (e.g., system-level requests),
  this provides a default user identity.

  Returns: `"00000000-0000-0000-0000-000000000002"`
  """
  def default_user_id, do: @default_user_id

  @doc """
  Extracts tenant context from a decoded NATS message.

  Falls back to the default tenant if `tenant_id` is absent (backward compatibility
  for messages from older nodes that don't include tenant fields).

  Returns a map with `:tenant_id`, `:user_id`, and `:role` keys. All values are
  strings (as decoded from NATS JSON).

  ## Examples

      iex> ctx = extract_context(%{"tenant_id" => "some-uuid", "user_id" => "user-1"})
      iex> ctx.tenant_id
      "some-uuid"
      iex> ctx.user_id
      "user-1"
      iex> ctx.role
      "user"

      iex> ctx = extract_context(%{})
      iex> ctx.tenant_id
      "00000000-0000-0000-0000-000000000001"
      iex> ctx.user_id
      nil
      iex> ctx.role
      "user"
  """
  def extract_context(message) when is_map(message) do
    %{
      tenant_id: message["tenant_id"] || @default_tenant_id,
      user_id: message["user_id"] || @default_user_id,
      role: message["role"] || "user"
    }
  end
end
