defmodule A2A.Standalone do
  @moduledoc """
  Boots [Bandit](https://hex.pm/packages/bandit) serving `A2A.Plug.Router` for
  zero-web-framework use. Drop it in a supervision tree:

      children = [
        {Phoenix.PubSub, name: MyApp.PubSub},
        {A2A.Server.Supervisor, name: MyAgent, executor: MyExecutor,
         pubsub: MyApp.PubSub, agent_card: MyAgent.card()},
        {A2A.Standalone, server: MyAgent, port: 4000}
      ]

  `bandit` is an OPTIONAL dependency; mounting `A2A.Plug.Router` into an existing
  Plug/Phoenix app needs no server dependency. This module raises if `bandit` is
  not loaded.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    server = Keyword.fetch!(opts, :server)
    port = Keyword.get(opts, :port, 4000)

    ensure_bandit!()

    Bandit.child_spec(
      plug: {A2A.Plug.Router, [server: server]},
      scheme: :http,
      port: port
    )
  end

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    %{start: {mod, fun, args}} = child_spec(opts)
    apply(mod, fun, args)
  end

  defp ensure_bandit! do
    Code.ensure_loaded?(Bandit) ||
      raise "A2A.Standalone requires the optional :bandit dependency. Add {:bandit, \"~> 1.5\"} to your deps."
  end
end
