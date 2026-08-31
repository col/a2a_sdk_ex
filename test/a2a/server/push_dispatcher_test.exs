defmodule A2A.Server.PushDispatcherTest do
  use ExUnit.Case, async: false
  alias A2A.Server.{DefaultHandler, PushConfigStore}
  alias A2A.Test.{CapturingSender, DelayingSender, PartialRaisingSender, RaisingPushStore, Wait}

  alias A2A.Types.{
    Message,
    Part,
    SendMessageConfiguration,
    SendMessageRequest,
    StreamResponse,
    Task,
    TaskPushNotificationConfig
  }

  setup do
    name = :"srv_disp_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_disp_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor,
       name: name,
       executor: A2A.Test.EchoExecutor,
       pubsub: pubsub,
       push_notifications: true,
       push_sender: CapturingSender}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    :ets.delete_all_objects(PushConfigStore.ETS)
    CapturingSender.attach(self())
    %{server: A2A.Server.handle(name)}
  end

  defp send_req(cfg) do
    %SendMessageRequest{
      message: %Message{
        message_id: "m_#{System.unique_integer([:positive])}",
        role: :user,
        parts: [Part.text("hi")]
      },
      configuration: %SendMessageConfiguration{task_push_notification_config: cfg}
    }
  end

  defp send_req, do: send_req(nil)

  # Spec 3.4.2 forbids a client-supplied taskId for creating a task, so tests
  # that need to know the id up front (to register a config against it, or to
  # look up its dispatcher) pin the server's generator instead.
  defp with_id(server, task_id), do: %{server | id_generator: fn -> task_id end}

  test "inline config: dispatcher POSTs each task event to the webhook (in order)", %{
    server: server
  } do
    cfg = %TaskPushNotificationConfig{url: "https://h/cb", token: "t"}
    {:ok, _task} = DefaultHandler.send_message(with_id(server, "task-1"), send_req(cfg))

    frames = collect_pushes([])
    # EchoExecutor emits: working (status) → artifact → completed (status)
    assert Enum.any?(frames, &match?(%StreamResponse{kind: :status_update}, &1))
    assert Enum.any?(frames, &match?(%StreamResponse{kind: :artifact_update}, &1))
    assert List.last(frames).status_update.status.state == :completed
  end

  test "a raising sender neither aborts a sibling delivery nor kills the dispatcher",
       %{server: server} do
    # Directly observe dispatcher SURVIVAL + CONTINUED DELIVERY: with a raising
    # config alongside a normal one, the normal config must still receive EVERY
    # event (incl. the terminal one that arrives after the earlier raise). Against
    # a non-crash-safe dispatch, the raise crashes the dispatcher mid-deliver, so
    # the normal config misses subsequent events → this fails.
    server = %{server | push_sender: PartialRaisingSender}
    PartialRaisingSender.attach(self())

    task_id = "task-partial-raise"

    for url <- ["https://raise/cb", "https://ok/cb"] do
      {:ok, _} =
        DefaultHandler.create_push_config(server, %TaskPushNotificationConfig{
          task_id: task_id,
          url: url
        })
    end

    {:ok, _task} =
      DefaultHandler.send_message(with_id(server, task_id), send_req())

    # Only the normal (non-raising) config forwards {:push, ...}.
    normal_frames = for {:push, %{url: "https://ok/cb"}, frame} <- collect_all_pushes([]), do: frame

    assert Enum.any?(normal_frames, &match?(%StreamResponse{kind: :status_update}, &1))
    assert Enum.any?(normal_frames, &match?(%StreamResponse{kind: :artifact_update}, &1))
    assert List.last(normal_frames).status_update.status.state == :completed

    # Second guard: the dispatcher survived (it self-stops on terminal, so allow
    # either "still registered" or "cleanly gone" — never a crash mid-stream, which
    # the missing-frames assertion above already rules out).
    assert match?([{_pid, _}], Registry.lookup(server.push_registry, task_id)) or
             Registry.lookup(server.push_registry, task_id) == []
  end

  test "push_timeout: :infinity does not crash the dispatcher (delivery still happens)", %{
    server: server
  } do
    server = %{server | push_timeout: :infinity}
    cfg = %TaskPushNotificationConfig{url: "https://h/cb", token: "t"}

    {:ok, _task} =
      DefaultHandler.send_message(with_id(server, "task-infinite-timeout"), send_req(cfg))

    frames = collect_pushes([])
    assert Enum.any?(frames, &match?(%StreamResponse{kind: :status_update}, &1))
    assert Enum.any?(frames, &match?(%StreamResponse{kind: :artifact_update}, &1))
    assert List.last(frames).status_update.status.state == :completed
  end

  test "inline registration is best-effort against a raising push_store.put (SendMessage still succeeds)",
       %{server: server} do
    server = %{server | push_store: RaisingPushStore}
    cfg = %TaskPushNotificationConfig{url: "https://h/cb", token: "t"}

    assert {:ok, %Task{} = task} =
             DefaultHandler.send_message(with_id(server, "task-raising-store"), send_req(cfg))

    assert task.status.state == :completed
  end

  test "inline config with an invalid url does not fail SendMessage", %{server: server} do
    cfg = %TaskPushNotificationConfig{url: "ftp://nope", token: "t"}

    assert {:ok, %Task{} = task} =
             DefaultHandler.send_message(with_id(server, "task-badurl"), send_req(cfg))

    assert task.status.state == :completed
  end

  test "multi-webhook fan-out: both webhooks get every event, all of event N before N+1",
       %{server: server} do
    server = %{server | push_sender: DelayingSender}
    DelayingSender.attach(self())
    # "slow" sleeps so a fire-and-forget impl would let "fast" of event N+1 overtake
    # "slow" of event N; the per-event barrier prevents that.
    DelayingSender.configure(%{"slow" => 40, "fast" => 0})

    task_id = "task-fanout"

    for id <- ["slow", "fast"] do
      {:ok, _} =
        DefaultHandler.create_push_config(server, %TaskPushNotificationConfig{
          id: id,
          task_id: task_id,
          url: "https://h/#{id}"
        })
    end

    {:ok, _task} =
      DefaultHandler.send_message(with_id(server, task_id), send_req())

    deliveries = collect_deliveries([])

    # Both webhooks saw all three EchoExecutor events, ending :completed.
    for id <- ["slow", "fast"] do
      frames = for {^id, f} <- deliveries, do: f
      assert length(frames) == 3
      assert List.last(frames).status_update.status.state == :completed
    end

    # Ordering barrier: derive each delivery's event ordinal (0,1,2) by counting
    # per id; in the global arrival order these ordinals must be non-decreasing —
    # i.e. every delivery of event N precedes any delivery of event N+1.
    {ordinals, _counts} =
      Enum.map_reduce(deliveries, %{}, fn {id, _frame}, counts ->
        n = Map.get(counts, id, 0)
        {n, Map.put(counts, id, n + 1)}
      end)

    assert ordinals == Enum.sort(ordinals)
  end

  test "a dispatcher survives an interrupted turn and pushes the next turn's terminal event",
       %{server: server} do
    # Push delivery is per TASK, not per turn: a task parked at `input_required`
    # is not over, so its dispatcher must keep delivering when the client answers.
    cfg = %TaskPushNotificationConfig{url: "https://h/cb", token: "t"}
    parked = %{with_id(server, "task-mt") | executor: A2A.Test.InputRequiredExecutor}

    {:ok, %Task{status: %{state: :input_required}}} =
      DefaultHandler.send_message(parked, send_req(cfg))

    first_turn = collect_pushes([])
    assert Enum.any?(first_turn, &match?(%StreamResponse{kind: :status_update}, &1))

    # Turn one's execution exits just after the blocking send returns; a second
    # turn started before then is rejected as :task_in_progress.
    Wait.for_no_execution(server, "task-mt")

    {:ok, %Task{status: %{state: :completed}}} =
      DefaultHandler.send_message(
        server,
        %SendMessageRequest{
          message: %Message{
            message_id: "m_#{System.unique_integer([:positive])}",
            role: :user,
            task_id: "task-mt",
            parts: [Part.text("answer")]
          }
        }
      )

    second_turn = collect_pushes([])

    assert Enum.any?(second_turn, fn
             %StreamResponse{kind: :status_update, status_update: %{status: %{state: s}}} ->
               s == :completed

             _ ->
               false
           end)
  end

  defp collect_pushes(acc) do
    receive do
      {:push, _cfg, frame} -> collect_pushes([frame | acc])
    after
      500 -> Enum.reverse(acc)
    end
  end

  defp collect_all_pushes(acc) do
    receive do
      {:push, _cfg, _frame} = msg -> collect_all_pushes([msg | acc])
    after
      500 -> Enum.reverse(acc)
    end
  end

  defp collect_deliveries(acc) do
    receive do
      {:delivered, id, frame} -> collect_deliveries([{id, frame} | acc])
    after
      500 -> Enum.reverse(acc)
    end
  end
end
