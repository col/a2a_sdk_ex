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
  alias A2A.Server.{ResultAssembler, TaskUpdater}

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

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:cancel, _from, %{arg: arg, updater: updater, child: child} = state) do
    # `state.updater.task` is only set at init/1 and is NOT advanced by the child's
    # execute/2 (the child runs on its own updater copy). Decide terminality from a
    # FRESH store read so a task that just completed — while this process is still
    # alive (the blocking drain returns on the terminal broadcast before we handle
    # the child :DOWN) — is not overwritten with :canceled.
    fresh = fresh_task(arg, updater)

    if fresh && ResultAssembler.terminal?(fresh) do
      {:reply, {:error, A2A.Error.not_cancelable(arg.task_id)},
       %{state | updater: %{updater | task: fresh}}}
    else
      # Stop the in-flight author work (unlinked child) before settling.
      stop_child(child)

      updater = %{updater | task: fresh || updater.task}
      updater = maybe_author_cancel(arg, updater)

      updater =
        if ResultAssembler.terminal?(updater.task),
          do: updater,
          else: TaskUpdater.update_status(updater, :canceled)

      {:stop, :normal, {:ok, updater.task}, %{state | updater: updater, child: nil}}
    end
  end

  defp fresh_task(arg, updater) do
    case updater.store.get(arg.task_id, updater.scope) do
      {:ok, task} -> task
      _ -> nil
    end
  end

  defp stop_child(nil), do: :ok

  defp stop_child({pid, ref}) do
    Process.demonitor(ref, [:flush])
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
  end

  defp maybe_author_cancel(arg, updater) do
    if function_exported?(arg.executor, :cancel, 2) do
      arg.executor.cancel(arg.context, updater)
      # The author emits via the updater's pubsub/store side effects; re-read the
      # projection from the store so a terminal the author emitted is reflected.
      case updater.store.get(arg.task_id, updater.scope) do
        {:ok, task} -> %{updater | task: task}
        _ -> updater
      end
    else
      updater
    end
  end

  defp format_down({%{__exception__: true} = e, _stack}), do: Exception.message(e)
  defp format_down({{:nocatch, value}, _stack}), do: "throw: #{inspect(value)}"
  defp format_down(other), do: "exit: #{inspect(other)}"
end
