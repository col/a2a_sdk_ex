defmodule A2A.Server.PushDispatcher.Supervisor do
  @moduledoc "DynamicSupervisor for per-task `A2A.Server.PushDispatcher` processes, plus idempotent `ensure_started/2` (keyed by task id via the server's push registry)."
  use DynamicSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: name)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Starts (or returns the existing) dispatcher for `task_id`. Idempotent."
  @spec ensure_started(A2A.Server.t(), String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(%A2A.Server{push_dyn_sup: sup, push_registry: reg} = server, task_id) do
    case Registry.lookup(reg, task_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec = {A2A.Server.PushDispatcher, %{server: server, task_id: task_id}}

        case DynamicSupervisor.start_child(sup, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end
end
