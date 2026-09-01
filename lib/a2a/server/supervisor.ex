defmodule A2A.Server.Supervisor do
  @moduledoc """
  The mountable OTP tree for one A2A server: PubSub (optional — reuse the host's),
  Registry, execution DynamicSupervisor, and the ETS TaskStore. Add it to your
  application's supervision tree, giving it a unique `:name` and your
  `A2A.Server.AgentExecutor` implementation:

      children = [
        {Phoenix.PubSub, name: MyApp.PubSub},
        {A2A.Server.Supervisor,
         name: MyAgent, executor: MyExecutor, pubsub: MyApp.PubSub}
      ]

  Other options: `:store` (custom `A2A.Server.TaskStore`, default ETS-backed),
  `:agent_card` (served at `/.well-known/agent-card.json`), `:scope` (default
  tenant/owner scope), `:drain_timeout` (blocking-call timeout), and
  `:push_notifications` (set `true` to enable push config storage/dispatch).
  """
  use Supervisor

  alias A2A.Server.PushSender

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

    push? = Keyword.get(opts, :push_notifications, false)
    push_registry = Module.concat(name, "PushRegistry")
    push_dyn_sup = Module.concat(name, "PushDispatcherSupervisor")

    handle = %A2A.Server{
      name: name,
      executor: Keyword.fetch!(opts, :executor),
      pubsub: pubsub,
      registry: Module.concat(name, "Registry"),
      dyn_sup: Module.concat(name, "ExecutionSupervisor"),
      store: store,
      scope: Keyword.get(opts, :scope, A2A.Scope.default()),
      id_generator: Keyword.get(opts, :id_generator, &A2A.Server.default_id/0),
      drain_timeout: Keyword.get(opts, :drain_timeout, :infinity),
      agent_card: Keyword.get(opts, :agent_card),
      push_notifications: push?,
      push_store: if(push?, do: Keyword.get(opts, :push_store, A2A.Server.PushConfigStore.ETS)),
      push_sender: if(push?, do: Keyword.get(opts, :push_sender, A2A.Server.PushSender.Default)),
      push_timeout: Keyword.get(opts, :push_timeout, 5_000),
      push_url_validator:
        if(push?,
          do: Keyword.get(opts, :push_url_validator, PushSender.default_url_validator())
        ),
      push_registry: if(push?, do: push_registry),
      push_dyn_sup: if(push?, do: push_dyn_sup)
    }

    A2A.Server.put_handle(handle)

    children =
      maybe_pubsub(pubsub) ++
        [
          {Registry, keys: :unique, name: handle.registry},
          {DynamicSupervisor, name: handle.dyn_sup, strategy: :one_for_one},
          store
        ] ++ push_children(push?, handle)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp push_children(false, _handle), do: []

  defp push_children(true, handle) do
    [
      handle.push_store,
      {Registry, keys: :unique, name: handle.push_registry},
      {A2A.Server.PushDispatcher.Supervisor, name: handle.push_dyn_sup}
    ]
  end

  # Start PubSub only if not already running (a Phoenix host passes its own).
  defp maybe_pubsub(pubsub) do
    case Process.whereis(pubsub) do
      nil -> [{Phoenix.PubSub, name: pubsub}]
      _pid -> []
    end
  end
end
