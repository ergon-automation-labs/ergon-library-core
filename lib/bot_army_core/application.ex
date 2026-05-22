defmodule BotArmyCore.Application do
  @moduledoc """
  BotArmyCore application supervisor.
  """

  use Application

  @env Mix.env()

  @impl true
  def start(_type, _args) do
    children = maybe_add_graph_repo()

    opts = [strategy: :one_for_one, name: BotArmyCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_graph_repo do
    if Application.get_env(:bot_army_library_core, :graph_enabled, false) &&
         @env != :test do
      # Use restart: :temporary so GraphRepo crash doesn't cycle/restart or crash the supervisor.
      # Graph is background/optional functionality — if it's unavailable, log a warning but keep the bot running.
      [Supervisor.child_spec(BotArmyCore.GraphRepo, restart: :temporary)]
    else
      []
    end
  end
end
