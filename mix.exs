defmodule A2A.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/col/a2a_sdk_ex"

  def project do
    [
      app: :a2a,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix]],
      name: "A2A",
      description: "Elixir SDK for building A2A (Agent2Agent) compliant agents.",
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExUnit],
      preferred_cli_env: ["test.proto": :test, precommit: :test]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.1", only: :test},
      {:protobuf, "~> 0.14", only: [:dev, :test], runtime: false},
      {:google_protos, "~> 0.4", only: [:dev, :test]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "test.proto": ["test --only proto"],
      # Run everything CI's toolchain-free `test` job enforces, fast checks first.
      # Mirrors the gate that must always be green; the proto group needs the
      # protoc toolchain and is run separately via `mix test.proto`.
      precommit: [
        "hex.audit",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test",
        "dialyzer"
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv/proto/PROTO_VERSION mix.exs README.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md", "docs/superpowers/specs/2026-08-29-data-model-and-codec-design.md"]
    ]
  end
end
