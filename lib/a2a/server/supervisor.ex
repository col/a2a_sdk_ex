defmodule A2A.Server.Supervisor do
  @moduledoc """
  The mountable OTP tree for one A2A server: PubSub (optional — reuse the host's),
  Registry, execution DynamicSupervisor, and the ETS TaskStore. Nothing is global;
  a host app can start several under different `:name`s.
  """
  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: Module.concat(name, "Supervisor"))
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    pubsub = Keyword.fetch!(opts, :pubsub)
    store = Keyword.get(opts, :store, A2A.Server.TaskStore.ETS)

    handle = %A2A.Server{
      name: name,
      executor: Keyword.fetch!(opts, :executor),
      pubsub: pubsub,
      registry: Module.concat(name, "Registry"),
      dyn_sup: Module.concat(name, "ExecutionSupervisor"),
      store: store,
      scope: Keyword.get(opts, :scope, A2A.Scope.default()),
      id_generator: Keyword.get(opts, :id_generator, &A2A.Server.default_id/0),
      drain_timeout: Keyword.get(opts, :drain_timeout, :infinity)
    }

    A2A.Server.put_handle(handle)

    children =
      maybe_pubsub(pubsub) ++
        [
          {Registry, keys: :unique, name: handle.registry},
          {DynamicSupervisor, name: handle.dyn_sup, strategy: :one_for_one},
          store
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Start PubSub only if not already running (a Phoenix host passes its own).
  defp maybe_pubsub(pubsub) do
    case Process.whereis(pubsub) do
      nil -> [{Phoenix.PubSub, name: pubsub}]
      _pid -> []
    end
  end
end
