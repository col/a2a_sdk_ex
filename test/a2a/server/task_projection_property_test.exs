defmodule A2A.Server.TaskProjectionPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias A2A.Server.ResultAssembler, as: RA
  alias A2A.Types.{Artifact, Part, TaskArtifactUpdateEvent, TaskStatus, TaskStatusUpdateEvent}

  defp event_gen(task_id) do
    StreamData.one_of([
      StreamData.map(StreamData.member_of([:working, :input_required]), fn s ->
        %TaskStatusUpdateEvent{task_id: task_id, status: %TaskStatus{state: s}}
      end),
      StreamData.map(StreamData.string(:alphanumeric, min_length: 1), fn t ->
        %TaskArtifactUpdateEvent{
          task_id: task_id,
          artifact: %Artifact{artifact_id: "a", parts: [Part.text(t)]},
          append: true
        }
      end)
    ])
  end

  property "any valid event sequence assembles to a JSON-round-trippable Task" do
    check all(events <- StreamData.list_of(event_gen("t"), max_length: 20)) do
      task = Enum.reduce(events, RA.init("t", "c"), &RA.apply(&2, &1))
      assert {:ok, json} = A2A.JSON.encode(task)
      assert {:ok, %A2A.Types.Task{}} = A2A.JSON.decode(json, A2A.Types.Task)
    end
  end
end
