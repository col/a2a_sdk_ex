defmodule A2A.Server.PushDispatcherTest do
  use ExUnit.Case, async: false
  alias A2A.Server.{DefaultHandler, PushConfigStore}

  alias A2A.Types.{
    Message,
    Part,
    SendMessageConfiguration,
    SendMessageRequest,
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
       push_sender: A2A.Test.CapturingSender}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    :ets.delete_all_objects(PushConfigStore.ETS)
    A2A.Test.CapturingSender.attach(self())
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
    assert Enum.any?(frames, &match?(%A2A.Types.StreamResponse{kind: :status_update}, &1))
    assert Enum.any?(frames, &match?(%A2A.Types.StreamResponse{kind: :artifact_update}, &1))
    assert List.last(frames).status_update.status.state == :completed
  end

  defp collect_pushes(acc) do
    receive do
      {:push, _cfg, frame} -> collect_pushes([frame | acc])
    after
      500 -> Enum.reverse(acc)
    end
  end
end
