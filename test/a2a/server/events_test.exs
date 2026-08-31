defmodule A2A.Server.EventsTest do
  use ExUnit.Case, async: true
  alias A2A.Server.Events
  alias A2A.Server.Events.Event

  alias A2A.Types.{
    Artifact,
    Message,
    Task,
    TaskArtifactUpdateEvent,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  defp status_event(state),
    do: %TaskStatusUpdateEvent{task_id: "t-1", status: %TaskStatus{state: state}}

  setup do
    pubsub = :"pubsub_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})
    %{pubsub: pubsub}
  end

  test "topic/1 namespaces by task id" do
    assert Events.topic("abc") == "a2a:task:abc"
  end

  test "subscribe then broadcast delivers the envelope", %{pubsub: pubsub} do
    :ok = Events.subscribe(pubsub, "t-1")

    evt = %Event{
      task_id: "t-1",
      context_id: "c",
      payload: %A2A.Types.Task{id: "t-1"},
      terminal?: false
    }

    :ok = Events.broadcast(pubsub, evt)
    assert_receive %Event{task_id: "t-1"}
  end

  describe "final?/1 — does this payload close a stream (§3.1.2, §3.1.6)" do
    test "a terminal status update is final" do
      for state <- [:completed, :failed, :canceled, :rejected] do
        assert Events.final?(status_event(state)), "expected #{state} to be final"
      end
    end

    test "interrupted and in-progress status updates are NOT final" do
      # §3.2.2 makes these end the *blocking* call; §3.1.2/§3.1.6 keep the stream open.
      for state <- [:submitted, :working, :input_required, :auth_required] do
        refute Events.final?(status_event(state)), "expected #{state} not to be final"
      end
    end

    test "a direct Message reply is final (§3.1.2 pattern 1)" do
      assert Events.final?(%Message{message_id: "m1", role: :agent, parts: []})
    end

    test "an artifact update is never final" do
      evt = %TaskArtifactUpdateEvent{task_id: "t-1", artifact: %Artifact{artifact_id: "a1"}}
      refute Events.final?(evt)
    end

    test "a Task payload follows its own status" do
      assert Events.final?(%Task{id: "t-1", status: %TaskStatus{state: :completed}})
      refute Events.final?(%Task{id: "t-1", status: %TaskStatus{state: :input_required}})
    end

    test "a status update with no status is not final" do
      refute Events.final?(%TaskStatusUpdateEvent{task_id: "t-1"})
    end
  end
end
