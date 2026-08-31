defmodule A2A.Server.PushDispatcherTest do
  use ExUnit.Case, async: false
  alias A2A.Server.{DefaultHandler, PushConfigStore}
  alias A2A.Test.{CapturingSender, DelayingSender, RaisingSender}

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

  defp send_req(task_id, cfg) do
    %SendMessageRequest{
      message: %Message{
        message_id: "m_#{System.unique_integer([:positive])}",
        role: :user,
        task_id: task_id,
        parts: [Part.text("hi")]
      },
      configuration: %SendMessageConfiguration{task_push_notification_config: cfg}
    }
  end

  test "inline config: dispatcher POSTs each task event to the webhook (in order)", %{
    server: server
  } do
    cfg = %TaskPushNotificationConfig{url: "https://h/cb", token: "t"}
    {:ok, _task} = DefaultHandler.send_message(server, send_req("task-1", cfg))

    frames = collect_pushes([])
    # EchoExecutor emits: working (status) → artifact → completed (status)
    assert Enum.any?(frames, &match?(%StreamResponse{kind: :status_update}, &1))
    assert Enum.any?(frames, &match?(%StreamResponse{kind: :artifact_update}, &1))
    assert List.last(frames).status_update.status.state == :completed
  end

  test "a raising sender does not take down the dispatcher or the task path", %{server: server} do
    server = %{server | push_sender: RaisingSender}
    cfg = %TaskPushNotificationConfig{url: "https://h/cb", token: "t"}

    # message/send must succeed to :completed — delivery is best-effort, the
    # raising sender is caught and logged, never propagated to the task path.
    assert {:ok, %Task{} = task} =
             DefaultHandler.send_message(server, send_req("task-raise", cfg))

    assert task.status.state == :completed

    # The dispatcher process (if still alive) and the whole tree survive: the
    # supervised server keeps serving — a second send on a fresh task works.
    assert {:ok, %Task{}} =
             DefaultHandler.send_message(server, send_req("task-raise-2", cfg))
  end

  test "inline config with an invalid url does not fail message/send", %{server: server} do
    cfg = %TaskPushNotificationConfig{url: "ftp://nope", token: "t"}

    assert {:ok, %Task{} = task} =
             DefaultHandler.send_message(server, send_req("task-badurl", cfg))

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
      DefaultHandler.send_message(server, %SendMessageRequest{
        message: %Message{
          message_id: "m_#{System.unique_integer([:positive])}",
          role: :user,
          task_id: task_id,
          parts: [Part.text("hi")]
        }
      })

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

  defp collect_pushes(acc) do
    receive do
      {:push, _cfg, frame} -> collect_pushes([frame | acc])
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
