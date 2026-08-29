defmodule A2A.Server.ExecutionTest.SlowExecutor do
  @moduledoc "Blocks briefly before completing, so its process outlives a racing second `start/3` call."
  @behaviour A2A.Server.AgentExecutor
  alias A2A.Server.TaskUpdater

  @impl true
  def execute(_ctx, updater) do
    Process.sleep(200)
    updater |> TaskUpdater.start_work() |> TaskUpdater.complete()
    :ok
  end

  @impl true
  def cancel(_ctx, _updater), do: :ok
end

defmodule A2A.Server.ExecutionTest do
  use ExUnit.Case, async: false
  alias A2A.Server.{Events, Execution, RequestContext, TaskStore}
  alias A2A.Server.Events.Event

  setup do
    pubsub = :"pubsub_#{System.unique_integer([:positive])}"
    registry = :"reg_#{System.unique_integer([:positive])}"
    dyn = :"dyn_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})
    start_supervised!({Registry, keys: :unique, name: registry})
    start_supervised!({DynamicSupervisor, name: dyn, strategy: :one_for_one})
    start_supervised!(TaskStore.ETS)
    :ets.delete_all_objects(TaskStore.ETS)
    %{pubsub: pubsub, registry: registry, dyn: dyn}
  end

  defp arg(executor, task_id, ctx_meta) do
    %{
      task_id: task_id,
      context_id: "c",
      executor: executor,
      context: %RequestContext{
        message: nil,
        task_id: task_id,
        context_id: "c",
        user: A2A.User.anonymous()
      },
      updater_opts: [pubsub: ctx_meta.pubsub, store: TaskStore.ETS],
      registry: ctx_meta.registry
    }
  end

  test "runs the executor to a completed task and registers under task_id", %{pubsub: pubsub} = m do
    :ok = Events.subscribe(pubsub, "t-1")
    {:ok, _pid} = Execution.start(m.dyn, m.registry, arg(A2A.Test.EchoExecutor, "t-1", m))
    assert_receive %Event{terminal?: true}, 1000
    assert {:ok, %{status: %{state: :completed}}} = TaskStore.ETS.get("t-1", A2A.Scope.default())
  end

  test "a second start for the same task_id is rejected", %{} = m do
    {:ok, _} =
      Execution.start(m.dyn, m.registry, arg(A2A.Server.ExecutionTest.SlowExecutor, "dup", m))

    assert {:error, {:already_started, _}} =
             Execution.start(
               m.dyn,
               m.registry,
               arg(A2A.Server.ExecutionTest.SlowExecutor, "dup", m)
             )
  end

  @tag :capture_log
  test "an executor raise transitions the task to failed", %{pubsub: pubsub} = m do
    :ok = Events.subscribe(pubsub, "boom")
    {:ok, _} = Execution.start(m.dyn, m.registry, arg(A2A.Test.BoomExecutor, "boom", m))

    assert_receive %Event{
                     terminal?: true,
                     payload: %A2A.Types.TaskStatusUpdateEvent{status: %{state: :failed}}
                   },
                   1000

    assert {:ok, %{status: %{state: :failed}}} = TaskStore.ETS.get("boom", A2A.Scope.default())
  end

  @tag :capture_log
  test "an executor throw transitions the task to failed and is not restarted",
       %{pubsub: pubsub} = m do
    :ok = Events.subscribe(pubsub, "thrown")
    {:ok, pid} = Execution.start(m.dyn, m.registry, arg(A2A.Test.ThrowExecutor, "thrown", m))
    ref = Process.monitor(pid)

    assert_receive %Event{
                     terminal?: true,
                     payload: %A2A.Types.TaskStatusUpdateEvent{status: %{state: :failed}}
                   },
                   1000

    assert {:ok, %{status: %{state: :failed}}} = TaskStore.ETS.get("thrown", A2A.Scope.default())

    # temporary: no restart is attempted, so the process simply stays dead
    # (it may already have exited by the time we observe it, hence :noproc).
    assert_receive {:DOWN, ^ref, :process, ^pid, reason} when reason in [:normal, :noproc]
    refute Process.alive?(pid)
  end

  @tag :capture_log
  test "an executor exit transitions the task to failed", %{pubsub: pubsub} = m do
    :ok = Events.subscribe(pubsub, "exited")
    {:ok, _} = Execution.start(m.dyn, m.registry, arg(A2A.Test.ExitExecutor, "exited", m))

    assert_receive %Event{
                     terminal?: true,
                     payload: %A2A.Types.TaskStatusUpdateEvent{status: %{state: :failed}}
                   },
                   1000

    assert {:ok, %{status: %{state: :failed}}} = TaskStore.ETS.get("exited", A2A.Scope.default())
  end
end
