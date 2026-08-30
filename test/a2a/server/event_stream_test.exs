defmodule A2A.Server.EventStreamTest do
  use ExUnit.Case, async: false
  alias A2A.Server.{Events, EventStream}
  alias A2A.Server.Events.Event
  alias A2A.Types.{Task, TaskStatus}

  setup do
    pubsub = :"pubsub_es_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})
    %{pubsub: pubsub, task_id: "t_#{System.unique_integer([:positive])}"}
  end

  defp ev(task_id, terminal?),
    do: %Event{
      task_id: task_id,
      context_id: "c",
      payload: %Task{id: task_id, status: %TaskStatus{state: (terminal? && :completed) || :working}},
      terminal?: terminal?
    }

  test "yields events in order and halts after a terminal event", %{pubsub: pubsub, task_id: id} do
    parent = self()

    consumer =
      spawn_link(fn ->
        stream = EventStream.stream(pubsub, id, subscribe?: true)
        send(parent, {:collected, Enum.to_list(stream)})
      end)

    # let the consumer subscribe before we broadcast
    Process.sleep(50)
    Events.broadcast(pubsub, ev(id, false))
    Events.broadcast(pubsub, ev(id, true))
    # after terminal — must NOT be delivered
    Events.broadcast(pubsub, ev(id, false))

    assert_receive {:collected, events}, 1000
    assert length(events) == 2
    assert [%Event{terminal?: false}, %Event{terminal?: true}] = events
    refute Process.alive?(consumer)
  end

  test "halts when the monitored process goes DOWN without a terminal event",
       %{pubsub: pubsub, task_id: id} do
    dead = spawn(fn -> :ok end)
    Process.sleep(20)
    refute Process.alive?(dead)

    stream = EventStream.stream(pubsub, id, monitor: dead, subscribe?: true)
    assert Enum.to_list(stream) == []
  end

  test "halts after a finite idle timeout and does not halt on :infinity",
       %{pubsub: pubsub, task_id: id} do
    stream = EventStream.stream(pubsub, id, idle_timeout: 50, subscribe?: true)
    assert Enum.to_list(stream) == []
  end

  test "unsubscribes on halt so later broadcasts are not delivered",
       %{pubsub: pubsub, task_id: id} do
    stream = EventStream.stream(pubsub, id, idle_timeout: 30, subscribe?: true)
    assert Enum.to_list(stream) == []
    # This process ran the stream; after halt it must be unsubscribed:
    Events.broadcast(pubsub, ev(id, false))
    refute_receive %Event{}, 100
  end
end
