defmodule BotArmyCore.Application do
  @moduledoc """
  BotArmyCore application supervisor.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = maybe_add_graph_repo()

    opts = [strategy: :one_for_one, name: BotArmyCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_graph_repo do
    # GraphRepo is now supervised by individual bots, not the library.
    # Each bot defines its own repo (e.g., BotArmyInternalDocs.GraphRepo)
    # to avoid configuration conflicts when multiple bots load the library.
    []
  end
end
