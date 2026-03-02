defmodule BotArmyCore.Application do
  @moduledoc """
  BotArmyCore application supervisor.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Supervisors and workers can be added here
    ]

    opts = [strategy: :one_for_one, name: BotArmyCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
