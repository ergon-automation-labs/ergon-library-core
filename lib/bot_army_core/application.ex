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
    if Application.get_env(:bot_army_core, :graph_enabled, false) &&
         Mix.env() != :test do
      [BotArmyCore.GraphRepo]
    else
      []
    end
  end
end
