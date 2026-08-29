defmodule A2A.Server.Execution do
  @moduledoc """
  The single process for a `task_id`. Runs the author's `execute/2` under a serial
  mailbox — the only writer of the task's live state — broadcasting and persisting
  each emitted event via the `TaskUpdater`. Temporary: an execution has no resume
  logic, so it must never be restarted — restarting would re-run `execute/2` and
  re-emit/re-persist duplicate events. Both normal completion and abnormal exit
  (raise, throw, exit) settle with `{:stop, :normal, state}` after failing the task.
  """
  use GenServer, restart: :temporary
  require Logger
  alias A2A.Server.TaskUpdater

  @spec start(atom(), atom(), map()) :: {:ok, pid()} | {:error, term()}
  def start(dyn_sup, _registry, arg) do
    DynamicSupervisor.start_child(dyn_sup, {__MODULE__, arg})
  end

  def start_link(%{task_id: task_id, registry: registry} = arg) do
    GenServer.start_link(__MODULE__, arg, name: {:via, Registry, {registry, task_id}})
  end

  @impl true
  def init(arg) do
    updater =
      TaskUpdater.new(
        arg.task_id,
        arg.context_id,
        Keyword.put_new(arg.updater_opts, :scope, A2A.Scope.default())
      )

    {:ok, %{arg: arg, updater: updater}, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, %{arg: arg, updater: updater} = state) do
    arg.executor.execute(arg.context, updater)
    {:stop, :normal, state}
  rescue
    e ->
      Logger.error("A2A execution #{arg.task_id} crashed: #{Exception.message(e)}")
      TaskUpdater.fail(updater, Exception.message(e))
      {:stop, :normal, state}
  catch
    kind, reason ->
      message = "#{kind}: #{inspect(reason)}"
      Logger.error("A2A execution #{arg.task_id} crashed: #{message}")
      TaskUpdater.fail(updater, message)
      {:stop, :normal, state}
  end
end
