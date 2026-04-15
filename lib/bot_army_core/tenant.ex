defmodule BotArmyCore.Tenant do
  @moduledoc """
  Tenant identity for the multi-tenant Bot Army system.

  Provides the default tenant UUID used during Phase 1 (single-tenant mode).
  In Phase 2+, this constant is used as the fallback for backward compatibility.
  """

  @default_tenant_id "00000000-0000-0000-0000-000000000001"

  @doc """
  Returns the default tenant UUID.

  During Phase 1, all operations use this default UUID to initialize the multi-tenant
  data layer without behavior change. In Phase 2+, this is the fallback for legacy
  messages and provides backward compatibility.

  Returns: `"00000000-0000-0000-0000-000000000001"`
  """
  def default_tenant_id, do: @default_tenant_id

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
      user_id: message["user_id"],
      role: message["role"] || "user"
    }
  end
end
