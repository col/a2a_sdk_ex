defmodule A2A.Server.EventsTest do
  use ExUnit.Case, async: true
  alias A2A.Server.Events
  alias A2A.Server.Events.Event

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
end
