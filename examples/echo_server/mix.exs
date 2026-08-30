defmodule EchoServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :echo_server,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {EchoServer.Application, []}]
  end

  defp deps do
    [
      {:a2a, path: "../.."},
      {:bandit, "~> 1.5"}
    ]
  end
end
