defmodule BotArmyCore.GraphRepo do
  use Ecto.Repo,
    otp_app: :bot_army_core,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Initialize the repository connection with Apache AGE configuration.

  This runs `after_connect` hooks that:
  1. Load the AGE extension
  2. Set the search path to ag_catalog so Cypher queries work correctly
  """
  def init(_, opts) do
    opts =
      Keyword.put(opts, :after_connect, fn conn ->
        # Load Apache AGE extension
        Postgrex.query!(conn, "LOAD 'age'", [])

        # Set search path so Cypher queries resolve correctly
        Postgrex.query!(conn, "SET search_path = ag_catalog, \"$user\", public", [])
      end)

    {:ok, opts}
  end
end
