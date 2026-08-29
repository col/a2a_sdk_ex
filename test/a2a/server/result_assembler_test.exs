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
    assert [%Artifact{artifact_id: "a", parts: [p1, p2]}] = task.artifacts
    assert p1.text == "one"
    assert p2.text == "two"
  end

  test "artifact update with append: false replaces an existing artifact wholesale" do
    task = RA.init("t", "c")
    a1 = %Artifact{artifact_id: "a", parts: [Part.text("one"), Part.text("two")]}
    a2 = %Artifact{artifact_id: "a", parts: [Part.text("fresh")]}
    task = RA.apply(task, %TaskArtifactUpdateEvent{task_id: "t", artifact: a1, append: false})
    task = RA.apply(task, %TaskArtifactUpdateEvent{task_id: "t", artifact: a2, append: false})
    assert [%Artifact{artifact_id: "a", parts: [only]}] = task.artifacts
    assert only.text == "fresh"
  end

  test "Task snapshot adopts id/context/status but preserves accumulated history and artifacts" do
    msg = %Message{message_id: "m", role: :agent, parts: [Part.text("hi")]}
    art = %Artifact{artifact_id: "a", parts: [Part.text("one")]}

    seeded =
      RA.init("old", "old-ctx")
      |> RA.apply(msg)
      |> RA.apply(%TaskArtifactUpdateEvent{task_id: "old", artifact: art, append: false})

    snapshot = %Task{
      id: "new",
      context_id: "new-ctx",
      status: %TaskStatus{state: :working}
    }

    task = RA.apply(seeded, snapshot)
    assert task.id == "new"
    assert task.context_id == "new-ctx"
    assert task.status.state == :working
    assert task.history == [msg]
    assert [%Artifact{artifact_id: "a"}] = task.artifacts
  end

  test "bare Message event is appended to history" do
    m1 = %Message{message_id: "m1", role: :user, parts: [Part.text("first")]}
    m2 = %Message{message_id: "m2", role: :agent, parts: [Part.text("second")]}
    task = RA.init("t", "c") |> RA.apply(m1) |> RA.apply(m2)
    assert task.history == [m1, m2]
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
