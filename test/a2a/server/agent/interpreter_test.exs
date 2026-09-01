defmodule A2A.Server.Agent.InterpreterTest do
  use ExUnit.Case, async: false

  import A2A.Server.Agent.Result
  alias A2A.Server.Agent.Interpreter
  alias A2A.Server.TaskStore.ETS, as: Store
  alias A2A.Server.TaskUpdater
  alias A2A.Types.{Part, Task}

  setup do
    pubsub = :"itp_pubsub_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})
    start_supervised!(Store)
    :ets.delete_all_objects(Store)

    updater =
      TaskUpdater.new("task-1", "ctx-1", pubsub: pubsub, store: Store)

    %{updater: updater}
  end

  defp final_task, do: elem(Store.get("task-1", A2A.Scope.default()), 1)

  test "artifacts then default-completed terminal", %{updater: u} do
    reply()
    |> artifact("out", "hello", metadata: %{"k" => "v"})
    |> Interpreter.run(u)

    task = final_task()
    assert %Task{status: %{state: :completed}} = task
    assert [%{name: "out", parts: [%Part{text: "hello"}], metadata: %{"k" => "v"}}] = task.artifacts
  end

  test "explicit complete with message + metadata", %{updater: u} do
    reply() |> complete(message: "done", metadata: %{"n" => 1}) |> Interpreter.run(u)

    task = final_task()
    assert %Task{status: %{state: :completed, message: msg}} = task
    assert [%Part{text: "done"}] = msg.parts
    assert %{"n" => 1} = msg.metadata
  end

  test "input_required is the terminal state", %{updater: u} do
    reply() |> message("need currency") |> input_required() |> Interpreter.run(u)

    assert %Task{
             status: %{state: :input_required, message: %{parts: [%Part{text: "need currency"}]}}
           } = final_task()
  end

  test "reject/fail map to their states", %{updater: u} do
    reply() |> fail("boom") |> Interpreter.run(u)
    assert %Task{status: %{state: :failed, message: %{parts: [%Part{text: "boom"}]}}} = final_task()
  end

  test "stream folds into one chunk-merged artifact", %{updater: u} do
    reply() |> stream("answer", ["a", "b", "c"], id: "s1") |> Interpreter.run(u)

    task = final_task()
    assert %Task{status: %{state: :completed}} = task
    assert [%{artifact_id: "s1", name: "answer", parts: parts}] = task.artifacts
    assert Enum.map(parts, & &1.text) == ["a", "b", "c"]
  end

  test "empty stream yields one empty artifact", %{updater: u} do
    reply() |> stream("answer", [], id: "s2") |> Interpreter.run(u)
    assert [%{artifact_id: "s2", parts: []}] = final_task().artifacts
  end

  test "buffered artifact precedes streamed artifact", %{updater: u} do
    reply()
    |> artifact("first", "x", id: "f1")
    |> stream("second", ["y"], id: "s3")
    |> Interpreter.run(u)

    assert ["f1", "s3"] = Enum.map(final_task().artifacts, & &1.artifact_id)
  end
end
