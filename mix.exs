defmodule BotArmyCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :bot_army_core,
      version: "0.3.5",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Optional: for documentation generation
      # docs: docs(),
      # Optional: for testing
      test_coverage: [tool: :excoveralls]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BotArmyCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # HTTP client for NATS and API communication
      {:httpoison, "~> 2.0"},
      # JSON encoding/decoding
      {:jason, "~> 1.4"},
      # Logging
      {:logger_json, "~> 5.1"},
      # Schema validation (optional - for runtime schema validation)
      {:ex_json_schema, "~> 0.10"},

      # Core infrastructure dependencies
      {:bot_army_runtime, path: "../bot_army_runtime"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:gnat, "~> 1.2"},
      {:elixir_uuid, "~> 1.2"},

      # Development/Test dependencies
      {:ex_doc, "~> 0.30", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test]},
      {:excoveralls, "~> 0.17", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  # Optional: Configure documentation generation
  # defp docs do
  #   [
  #     main: "BotArmyCore",
  #     extras: ["README.md"]
  #   ]
  # end
end
