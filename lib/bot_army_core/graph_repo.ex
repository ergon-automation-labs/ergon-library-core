defmodule BotArmyCore.GraphRepo do
  @moduledoc "Ecto repo backed by PostgreSQL with Apache AGE extension for graph queries."
  use Ecto.Repo,
    otp_app: :bot_army_core,
    adapter: Ecto.Adapters.Postgres

  require Logger

  @doc """
  Initialize the repository connection with Apache AGE configuration.

  This runs `after_connect` hooks that:
  1. Load the AGE extension
  2. Set the search path to ag_catalog so Cypher queries work correctly

  If AGE is unavailable (not installed or database not ready), logs a warning
  but does not crash — graph operations are background/optional functionality.
  """
  def init(_, opts) do
    opts =
      Keyword.put(opts, :after_connect, fn conn ->
        try do
          # Load Apache AGE extension
          Postgrex.query!(conn, "LOAD 'age'", [])

          # Set search path so Cypher queries resolve correctly
          Postgrex.query!(conn, "SET search_path = ag_catalog, \"$user\", public", [])
        rescue
          e ->
            Logger.warning(
              "[GraphRepo] AGE extension unavailable or error during init: #{inspect(e)}"
            )
        end
      end)

    {:ok, opts}
  end
end
