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
end
