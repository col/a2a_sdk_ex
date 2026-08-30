defmodule A2A.Server.Execution do
  @moduledoc """
  The single process for a `task_id`. Runs the author's `execute/2` in an
  **unlinked, monitored child process**, keeping this GenServer's mailbox free to
  handle a `:cancel` call while the author's work is in flight. The GenServer is
  the task's serial state owner; it stays alive until the child finishes, then
  stops `:normal`. `restart: :temporary` — a completed/failed execution must
  never re-run. An author raise/throw/exit surfaces as a non-normal child
  `:DOWN`, which fails the task once and then stops normally.
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

    {:ok, %{arg: arg, updater: updater, child: nil}, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, %{arg: arg} = state) do
    {pid, ref} = spawn_monitor(fn -> arg.executor.execute(arg.context, state.updater) end)
    {:noreply, %{state | child: {pid, ref}}}
  end

  # Child finished — normal end stops us normally; abnormal end fails the task first.
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{child: {_, ref}} = state) do
    case reason do
      :normal ->
        {:stop, :normal, state}

      other ->
        message = format_down(other)
        Logger.error("A2A execution #{state.arg.task_id} crashed: #{message}")
        TaskUpdater.fail(state.updater, message)
        {:stop, :normal, state}
    end
  end

  # --- cancel lands in Task 6 as handle_call(:cancel, ...) ---

  defp format_down({%{__exception__: true} = e, _stack}), do: Exception.message(e)
  defp format_down(other), do: inspect(other)
end
