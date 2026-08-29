defmodule A2A.Types.EventsTest do
  use ExUnit.Case, async: true

  alias A2A.Types.{
    Artifact,
    StreamResponse,
    Task,
    TaskArtifactUpdateEvent,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  test "TaskStatusUpdateEvent field spec" do
    by_name = Map.new(TaskStatusUpdateEvent.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "task_id", number: 1, json_name: "taskId"} = by_name.task_id
    assert %{proto_name: "context_id", number: 2} = by_name.context_id
    assert %{proto_name: "status", number: 3, type: {:message, TaskStatus}} = by_name.status
    assert %{proto_name: "metadata", number: 4, type: :struct} = by_name.metadata
    assert TaskStatusUpdateEvent.__a2a_proto_name__() == "TaskStatusUpdateEvent"
  end

  test "TaskArtifactUpdateEvent field spec incl. bools" do
    by_name = Map.new(TaskArtifactUpdateEvent.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "artifact", number: 3, type: {:message, Artifact}} = by_name.artifact
    assert %{proto_name: "append", number: 4, type: :bool} = by_name.append

    assert %{proto_name: "last_chunk", number: 5, type: :bool, json_name: "lastChunk"} =
             by_name.last_chunk
  end

  test "StreamResponse is a payload-oneof union" do
    t = %Task{id: "t1"}
    sr = StreamResponse.task(t)
    assert %StreamResponse{kind: :task, task: ^t} = sr
    by_name = Map.new(StreamResponse.__a2a_fields__(), &{&1.name, &1})

    assert %{
             proto_name: "task",
             number: 1,
             type: {:message, Task},
             oneof: {:payload, :task},
             presence: :explicit
           } = by_name.task

    assert %{
             proto_name: "status_update",
             number: 3,
             oneof: {:payload, :status_update},
             json_name: "statusUpdate"
           } = by_name.status_update

    assert StreamResponse.__a2a_discriminator__() == :kind
    assert StreamResponse.__a2a_proto_name__() == "StreamResponse"
  end
end
