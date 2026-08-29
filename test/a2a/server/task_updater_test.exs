defmodule A2A.Server.TaskUpdaterTest do
  use ExUnit.Case, async: false
  alias A2A.Server.{Events, TaskStore, TaskUpdater}
  alias A2A.Server.Events.Event
  alias A2A.Types.Part

  setup do
    pubsub = :"pubsub_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})
    start_supervised!(TaskStore.ETS)
    :ets.delete_all_objects(TaskStore.ETS)
    :ok = Events.subscribe(pubsub, "t-1")
    u = TaskUpdater.new("t-1", "c-1", pubsub: pubsub, store: TaskStore.ETS)
    %{updater: u, pubsub: pubsub}
  end

  test "start_work broadcasts a working status and persists", %{updater: u} do
    TaskUpdater.start_work(u)
    assert_receive %Event{task_id: "t-1", terminal?: false}
    assert {:ok, %{status: %{state: :working}}} = TaskStore.ETS.get("t-1", A2A.Scope.default())
  end

  test "complete emits a terminal event and every emitted payload round-trips through JSON", %{
    updater: u
  } do
    u = TaskUpdater.start_work(u)
    u = TaskUpdater.add_artifact(u, Part.text("out"))
    TaskUpdater.complete(u, Part.text("done"))

    assert_receive %Event{payload: p1}
    assert {:ok, _} = json_roundtrip(p1)
    assert_receive %Event{payload: p2}
    assert {:ok, _} = json_roundtrip(p2)
    assert_receive %Event{payload: p3, terminal?: true}
    assert {:ok, _} = json_roundtrip(p3)
    assert {:ok, %{status: %{state: :completed}}} = TaskStore.ETS.get("t-1", A2A.Scope.default())
  end

  test "requires_input is terminal for the blocking drain", %{updater: u} do
    u = TaskUpdater.start_work(u)
    TaskUpdater.requires_input(u)
    assert_receive %Event{terminal?: false}

    assert_receive %Event{
      terminal?: true,
      payload: %A2A.Types.TaskStatusUpdateEvent{status: %{state: :input_required}}
    }
  end

  defp json_roundtrip(struct) do
    with {:ok, json} <- A2A.JSON.encode(struct),
         {:ok, _} <- A2A.JSON.decode(json, struct.__struct__),
         do: {:ok, :roundtripped}
  end
end
