defmodule A2A.Server.StreamingTest do
  use ExUnit.Case, async: false
  alias A2A.Server.DefaultHandler
  alias A2A.Test.{GatedExecutor, Wait}
  alias A2A.Types.{Message, Part, SendMessageRequest}

  setup do
    name = :"srv_stream_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_stream_#{System.unique_integer([:positive])}"

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

  test "blocking send_message still runs to completion on the reshaped path",
       %{server: server} do
    assert {:ok, %A2A.Types.Task{status: %{state: :completed}}} =
             DefaultHandler.send_message(server, req("hi"))
  end

  test "a finite per-request drain_timeout on a silent task yields :timeout",
       %{server: server} do
    # SilentExecutor never emits and never returns quickly; the idle timeout fires.
    server = %{server | executor: A2A.Test.SilentExecutor}

    assert {:error, %A2A.Error{code: :timeout}} =
             DefaultHandler.send_message(server, req("x"), drain_timeout: 50)
  end

  test "blocking send_message returns at auth_required, not just input_required",
       %{server: server} do
    # §3.2.2: a blocking send waits for a terminal state OR an interrupted state
    # (`input_required`, `auth_required`). The finite drain_timeout is the trap:
    # if auth_required is not treated as interrupted, this hangs and then fails
    # with :timeout rather than returning the task.
    server = %{server | executor: A2A.Test.AuthOnlyExecutor}

    assert {:ok, %A2A.Types.Task{status: %{state: :auth_required}}} =
             DefaultHandler.send_message(server, req("go"), drain_timeout: 1_000)
  end

  test "send_message_stream yields ordered StreamResponse frames ending in completed",
       %{server: server} do
    frames = server |> DefaultHandler.send_message_stream(req("hi")) |> Enum.to_list()

    assert Enum.all?(frames, &match?(%A2A.Types.StreamResponse{}, &1))
    # EchoExecutor: start_work (working status) → add_artifact → complete
    assert Enum.any?(frames, &match?(%A2A.Types.StreamResponse{kind: :status_update}, &1))
    assert Enum.any?(frames, &match?(%A2A.Types.StreamResponse{kind: :artifact_update}, &1))

    last = List.last(frames)

    assert %A2A.Types.StreamResponse{
             kind: :status_update,
             status_update: %{status: %{state: :completed}}
           } =
             last
  end

  test "every streamed frame round-trips through A2A.JSON", %{server: server} do
    frames = server |> DefaultHandler.send_message_stream(req("hi")) |> Enum.to_list()

    for frame <- frames do
      json = A2A.JSON.encode!(frame)
      assert {:ok, %A2A.Types.StreamResponse{}} = A2A.JSON.decode(json, A2A.Types.StreamResponse)
    end
  end

  test "a stream stays open through auth_required and input_required, closing at terminal",
       %{server: server} do
    # §3.1.2: "The stream MUST close when the task reaches a terminal state". An
    # interrupted state is not terminal — the client answers on a separate request
    # and the next turn's frames arrive on this same stream.
    server = %{server | executor: A2A.Test.AuthThenInputExecutor, id_generator: fn -> "sm1" end}
    caller = self()

    stream = DefaultHandler.send_message_stream(server, req("go"))

    # Turn two completes the task, from another process (this one must enumerate).
    spawn_link(fn ->
      Wait.for_no_execution(server, "sm1")
      echo = %{server | executor: A2A.Test.EchoExecutor}
      send(caller, {:turn_two, DefaultHandler.send_message(echo, req("more", task_id: "sm1"))})
    end)

    states =
      for %A2A.Types.StreamResponse{kind: :status_update, status_update: %{status: %{state: s}}} <-
            Enum.to_list(stream),
          do: s

    assert :auth_required in states
    assert :input_required in states
    assert List.last(states) == :completed
    assert_receive {:turn_two, {:ok, _}}, 2000
  end

  test "a parked stream is bounded by stream_idle_timeout", %{server: server} do
    # Nobody ever answers the input request, so nothing closes the stream but the
    # idle timeout. Without it the SSE request process would be held indefinitely.
    server = %{
      server
      | executor: A2A.Test.AuthThenInputExecutor,
        stream_idle_timeout: 250
    }

    frames = server |> DefaultHandler.send_message_stream(req("go")) |> Enum.to_list()

    last = List.last(frames)
    assert %A2A.Types.StreamResponse{kind: :status_update} = last
    assert last.status_update.status.state == :input_required
  end

  test "resubscribe on a finished task is rejected", %{server: server} do
    # Spec 3.1.6: SubscribeToTask "returns UnsupportedOperationError if the task
    # is in a terminal state" — a snapshot-only stream is not a substitute, since
    # a subscriber cannot tell it apart from a task that is merely quiet.
    {:ok, %A2A.Types.Task{id: id}} = DefaultHandler.send_message(server, req("hi"))

    assert {:error, %A2A.Error{code: :unsupported_operation}} =
             DefaultHandler.resubscribe(server, %A2A.Types.SubscribeToTaskRequest{id: id})
  end

  test "resubscribe on an unknown task returns not_found", %{server: server} do
    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.resubscribe(server, %A2A.Types.SubscribeToTaskRequest{id: "nope"})
  end

  test "resubscribe on a live task yields snapshot then subsequent live frames",
       %{server: server} do
    # The GatedExecutor is keyed by task id and the test must know it up front,
    # so the id is pinned through the server's generator rather than by sending
    # a client-supplied taskId, which spec 3.4.2 forbids for task creation.
    server = %{server | executor: GatedExecutor, id_generator: fn -> "live1" end}
    caller = self()

    # Start a streaming send that will pause after start_work until released.
    spawn_link(fn ->
      stream = DefaultHandler.send_message_stream(server, req("go"))
      send(caller, {:frames, Enum.to_list(stream)})
    end)

    # Wait until the task has started and persisted a snapshot.
    wait_for_task(server, "live1")

    {:ok, resub} =
      DefaultHandler.resubscribe(server, %A2A.Types.SubscribeToTaskRequest{id: "live1"})

    # Release the executor so it completes; collect the resubscribe frames.
    GatedExecutor.release("live1")
    frames = Enum.to_list(resub)

    assert [%A2A.Types.StreamResponse{kind: :task} | _rest] = frames
    assert List.last(frames).status_update.status.state == :completed
    assert_receive {:frames, _}, 1000
  end

  test "resubscribe to a parked task streams the NEXT turn's frames through terminal",
       %{server: server} do
    # TCK STREAM-SUB-002 (spec §3.1.6): the stream "MUST terminate when the task
    # reaches a terminal state". Turn one parks at `input_required` and its
    # execution process EXITS — so there is no live execution to attach to when
    # the subscription opens. The stream must still be live, and must carry the
    # follow-up turn's completion.
    parked = %{server | executor: A2A.Test.InputRequiredExecutor, id_generator: fn -> "sub1" end}

    assert {:ok, %A2A.Types.Task{id: "sub1", status: %{state: :input_required}}} =
             DefaultHandler.send_message(parked, req("turn one"))

    # The blocking send returned on the input_required *event*; the execution
    # process exits a moment later. Wait for it, so this really is the "no live
    # execution" case the TCK exercises — and so turn two is not rejected as
    # :task_in_progress.
    Wait.for_no_execution(server, "sub1")
    assert Registry.lookup(server.registry, "sub1") == []

    # Subscribe in THIS process — the stream is bound to the subscriber's mailbox.
    {:ok, stream} =
      DefaultHandler.resubscribe(server, %A2A.Types.SubscribeToTaskRequest{id: "sub1"})

    caller = self()

    spawn_link(fn ->
      send(
        caller,
        {:turn_two, DefaultHandler.send_message(server, req("turn two", task_id: "sub1"))}
      )
    end)

    frames = Enum.to_list(stream)

    # §3.1.6: a Task snapshot first, then live frames, terminal last.
    assert [
             %A2A.Types.StreamResponse{kind: :task, task: %{status: %{state: :input_required}}}
             | rest
           ] =
             frames

    assert rest != []
    last = List.last(frames)
    assert %A2A.Types.StreamResponse{kind: :status_update} = last
    assert last.status_update.status.state == :completed
    assert_receive {:turn_two, {:ok, _}}, 2000
  end

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
