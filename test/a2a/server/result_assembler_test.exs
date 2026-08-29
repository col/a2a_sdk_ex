defmodule A2A.Server.ResultAssemblerTest do
  use ExUnit.Case, async: true
  alias A2A.Server.ResultAssembler, as: RA

  alias A2A.Types.{
    Artifact,
    Message,
    Part,
    Task,
    TaskArtifactUpdateEvent,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  test "init/2 makes an empty submitted task" do
    assert %Task{id: "t", context_id: "c", status: %TaskStatus{state: :submitted}} =
             RA.init("t", "c")
  end

  test "status update replaces status and appends the status message to history" do
    msg = %Message{message_id: "m", role: :agent, parts: [Part.text("hi")]}
    evt = %TaskStatusUpdateEvent{task_id: "t", status: %TaskStatus{state: :working, message: msg}}
    task = RA.apply(RA.init("t", "c"), evt)
    assert task.status.state == :working
    assert task.history == [msg]
  end

  test "artifact update merges by artifact_id" do
    task = RA.init("t", "c")
    a1 = %Artifact{artifact_id: "a", parts: [Part.text("one")]}
    a2 = %Artifact{artifact_id: "a", parts: [Part.text("two")]}
    task = RA.apply(task, %TaskArtifactUpdateEvent{task_id: "t", artifact: a1, append: false})
    task = RA.apply(task, %TaskArtifactUpdateEvent{task_id: "t", artifact: a2, append: true})
    assert [%Artifact{artifact_id: "a", parts: [_, _]}] = task.artifacts
  end

  test "terminal task is frozen" do
    done =
      RA.apply(RA.init("t", "c"), %TaskStatusUpdateEvent{
        task_id: "t",
        status: %TaskStatus{state: :completed}
      })

    assert RA.terminal?(done)

    still =
      RA.apply(done, %TaskStatusUpdateEvent{task_id: "t", status: %TaskStatus{state: :working}})

    assert still.status.state == :completed
  end
end
