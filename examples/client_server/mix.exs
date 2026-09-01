defmodule ClientServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :client_server,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {ClientServer.Application, []}]
  end

  defp deps do
    [
      {:a2a_sdk, path: "../.."},
      {:bandit, "~> 1.5"},
      {:req, "~> 0.7"}
    ]
  end
end
