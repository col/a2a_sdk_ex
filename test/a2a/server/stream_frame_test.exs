defmodule A2A.Server.StreamFrameTest do
  use ExUnit.Case, async: true
  alias A2A.Server.StreamFrame

  alias A2A.Types.{
    Message,
    Part,
    StreamResponse,
    Task,
    TaskArtifactUpdateEvent,
    TaskStatusUpdateEvent
  }

  test "maps each event payload to the matching StreamResponse arm" do
    assert %StreamResponse{kind: :task} = StreamFrame.of(%Task{id: "t"})

    assert %StreamResponse{kind: :message} =
             StreamFrame.of(%Message{message_id: "m", role: :agent, parts: [Part.text("x")]})

    assert %StreamResponse{kind: :status_update} =
             StreamFrame.of(%TaskStatusUpdateEvent{task_id: "t"})

    assert %StreamResponse{kind: :artifact_update} =
             StreamFrame.of(%TaskArtifactUpdateEvent{task_id: "t"})
  end
end
