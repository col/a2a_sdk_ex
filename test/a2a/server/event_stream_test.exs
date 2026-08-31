defmodule A2A.Server.EventStreamTest do
  use ExUnit.Case, async: false
  alias A2A.Server.{Events, EventStream}
  alias A2A.Server.Events.Event
  alias A2A.Types.{TaskStatus, TaskStatusUpdateEvent}

  setup do
    pubsub = :"pubsub_es_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})
    %{pubsub: pubsub, task_id: "t_#{System.unique_integer([:positive])}"}
  end

  defp ev(task_id, state),
    do: %Event{
      task_id: task_id,
      context_id: "c",
      payload: %TaskStatusUpdateEvent{task_id: task_id, status: %TaskStatus{state: state}}
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
    Events.broadcast(pubsub, ev(id, :working))
    Events.broadcast(pubsub, ev(id, :completed))
    # after terminal — must NOT be delivered
    Events.broadcast(pubsub, ev(id, :working))

    assert_receive {:collected, events}, 1000
    assert length(events) == 2
    assert [%Event{}, %Event{}] = events
    assert List.last(events).payload.status.state == :completed
    refute Process.alive?(consumer)
  end

  test "does NOT halt on interrupted states — the stream survives to the next turn",
       %{pubsub: pubsub, task_id: id} do
    # §3.1.2/§3.1.6: only terminal states close a stream. `input_required` and
    # `auth_required` end a BLOCKING caller's wait (§3.2.2), not the stream.
    parent = self()

    spawn_link(fn ->
      stream = EventStream.stream(pubsub, id, subscribe?: true)
      send(parent, {:collected, Enum.to_list(stream)})
    end)

    Process.sleep(50)
    Events.broadcast(pubsub, ev(id, :auth_required))
    Events.broadcast(pubsub, ev(id, :input_required))
    # a later turn on the same task, arriving after the interruption
    Events.broadcast(pubsub, ev(id, :working))
    Events.broadcast(pubsub, ev(id, :completed))

    assert_receive {:collected, events}, 1000

    assert Enum.map(events, & &1.payload.status.state) ==
             [:auth_required, :input_required, :working, :completed]
  end

  test "halts after a direct Message reply (§3.1.2 pattern 1)",
       %{pubsub: pubsub, task_id: id} do
    parent = self()

    spawn_link(fn ->
      stream = EventStream.stream(pubsub, id, subscribe?: true)
      send(parent, {:collected, Enum.to_list(stream)})
    end)

    Process.sleep(50)

    Events.broadcast(pubsub, %Event{
      task_id: id,
      context_id: "c",
      payload: %A2A.Types.Message{message_id: "m1", role: :agent, parts: []}
    })

    Events.broadcast(pubsub, ev(id, :working))

    assert_receive {:collected, [%Event{payload: %A2A.Types.Message{}}]}, 1000
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
    Events.broadcast(pubsub, ev(id, :completed))
    refute_receive %Event{}, 100
  end
end
