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

  ## Options

    * `:server` (required) — the `A2A.Server.Supervisor` `:name` whose handle the
      router serves.
    * `:port` — convenience default for the listen port (`4000`). Equivalent to
      `bandit: [port: ...]`; a `:port` inside `:bandit` takes precedence.
    * `:bandit` — a keyword list passed straight through to `Bandit.child_spec/1`,
      giving access to Bandit's full option surface (scheme, TLS, ip, HTTP/1 and
      HTTP/2 tuning, `:thousand_island_options`, …). The `:plug` is always set by
      this module and cannot be overridden here.

  To serve HTTPS, configure Bandit under `:bandit`:

      {A2A.Standalone,
       server: MyAgent,
       bandit: [
         scheme: :https,
         port: 4443,
         thousand_island_options: [
           transport_options: [
             certfile: "priv/cert/selfsigned.pem",
             keyfile: "priv/cert/selfsigned_key.pem"
           ]
         ]
       ]}

  `bandit` is an OPTIONAL dependency; mounting `A2A.Plug.Router` into an existing
  Plug/Phoenix app needs no server dependency. This module raises if `bandit` is
  not loaded.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    server = Keyword.fetch!(opts, :server)
    port = Keyword.get(opts, :port, 4000)

    ensure_bandit!()

    opts
    |> Keyword.get(:bandit, [])
    |> Keyword.put_new(:port, port)
    |> Keyword.put(:plug, {A2A.Plug.Router, [server: server]})
    |> Bandit.child_spec()
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
