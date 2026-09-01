defmodule A2A.Server.SubscriptionIsolationTest do
  @moduledoc """
  A subscription is owned by a *process* mailbox, but a task topic is only one of
  many a process may be subscribed to, and the blocking drain stops reading before
  the executor stops emitting (§3.2.2 halts at the first interrupted state, while
  §3.1.2/§3.1.6 keep the task itself going). Both facts together let one operation's
  leftover `%Event{}` be consumed by the *next* one in the same process.

  The HTTP bindings hide this — Bandit gives every request its own process — and so
  does ExUnit, which gives every test one. These two tests deliberately drive two
  operations from a single process, which is what an in-process caller of
  `A2A.Server.DefaultHandler.send_message/2` does.
  """
  use ExUnit.Case, async: false

  alias A2A.Server.DefaultHandler
  alias A2A.Test.{GatedExecutor, Wait}
  alias A2A.Types.{Message, Part, SendMessageRequest, StreamResponse, SubscribeToTaskRequest, Task}

  setup do
    name = :"srv_iso_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_iso_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{server: A2A.Server.handle(name)}
  end

  defp req(text, opts \\ []) do
    %SendMessageRequest{
      message: %Message{
        message_id: "m_#{System.unique_integer([:positive])}",
        role: :user,
        task_id: Keyword.get(opts, :task_id),
        parts: [Part.text(text)]
      }
    }
  end

  test "a blocking turn two is not decided by turn one's leftover event", %{server: server} do
    # `AuthThenInputExecutor` emits `auth_required` and then `input_required`. §3.2.2
    # ends the blocking wait at the first of those, so the drain stops reading while
    # the executor is still running: the `input_required` broadcast arrives after the
    # fold halted. Turn two, from this same process, must fold ITS OWN events — if it
    # picks up turn one's leftover it halts immediately and reports `input_required`
    # for a turn that in fact ran to `completed`.
    parked = %{server | executor: A2A.Test.AuthThenInputExecutor, id_generator: fn -> "iso1" end}

    assert {:ok, %Task{id: "iso1", status: %{state: :auth_required}}} =
             DefaultHandler.send_message(parked, req("turn one"))

    Wait.for_no_execution(server, "iso1")

    assert {:ok, %Task{id: "iso1", status: %{state: :completed}}} =
             DefaultHandler.send_message(server, req("turn two", task_id: "iso1"))
  end

  test "a stream for one task never yields another task's frames", %{server: server} do
    # Task A is parked at `input_required` and this process holds a live subscription
    # to it (a `resubscribe/2` stream, not yet enumerated — the same shape a blocking
    # drain's leftover subscription leaves behind). Task B's stream then runs in this
    # process too. `EventStream` must not treat A's envelopes as B's: A's terminal
    # event would both leak A's frames onto B's stream and close it early.
    parked = %{server | executor: A2A.Test.InputRequiredExecutor, id_generator: fn -> "isoA" end}

    assert {:ok, %Task{id: "isoA", status: %{state: :input_required}}} =
             DefaultHandler.send_message(parked, req("A turn one"))

    Wait.for_no_execution(server, "isoA")

    {:ok, _a_stream} = DefaultHandler.resubscribe(server, %SubscribeToTaskRequest{id: "isoA"})

    gated = %{server | executor: GatedExecutor, id_generator: fn -> "isoB" end}
    b_stream = DefaultHandler.send_message_stream(gated, req("B go"))

    wait_for_task(server, "isoB")

    caller = self()

    spawn_link(fn ->
      # Drive task A to completion FIRST, so its frames are already in this test
      # process's mailbox when B's stream is enumerated, then let B finish.
      result = DefaultHandler.send_message(server, req("A turn two", task_id: "isoA"))
      send(caller, {:a_turn_two, result})
      GatedExecutor.release("isoB")
    end)

    frames = Enum.to_list(b_stream)

    assert_receive {:a_turn_two, {:ok, %Task{status: %{state: :completed}}}}, 2_000

    assert frames != []

    assert Enum.all?(frames, &(frame_task_id(&1) == "isoB")),
           "task B's stream carried foreign frames: #{inspect(Enum.map(frames, &frame_task_id/1))}"

    last = List.last(frames)
    assert %StreamResponse{kind: :status_update} = last
    assert last.status_update.status.state == :completed
  end

  defp frame_task_id(%StreamResponse{kind: :task, task: %Task{id: id}}), do: id
  defp frame_task_id(%StreamResponse{kind: :status_update, status_update: e}), do: e.task_id
  defp frame_task_id(%StreamResponse{kind: :artifact_update, artifact_update: e}), do: e.task_id
  defp frame_task_id(%StreamResponse{kind: :message}), do: :message

  defp wait_for_task(server, id, tries \\ 50) do
    case server.store.get(id, server.scope) do
      {:ok, _} ->
        :ok

      _ when tries > 0 ->
        Process.sleep(20)
        wait_for_task(server, id, tries - 1)

      _ ->
        flunk("task #{id} never appeared in store")
    end
  end
end
