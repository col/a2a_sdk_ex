defmodule A2A.Server.PushE2ETest do
  use ExUnit.Case, async: false
  alias A2A.Server.DefaultHandler

  alias A2A.Test.WebhookReceiver

  alias A2A.Types.{
    Message,
    Part,
    SendMessageConfiguration,
    SendMessageRequest,
    TaskPushNotificationConfig
  }

  @moduletag :integration

  setup do
    name = :"srv_e2e_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_e2e_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor,
       name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub, push_notifications: true}
    )

    :ets.delete_all_objects(A2A.Server.PushConfigStore.ETS)
    %{server: A2A.Server.handle(name)}
  end

  test "SendMessage with inline config delivers real webhooks ending in completed", %{
    server: server
  } do
    {base, srv} = WebhookReceiver.start(self())
    on_exit(fn -> Process.exit(srv, :normal) end)

    cfg = %TaskPushNotificationConfig{url: base <> "/cb", token: "t"}

    req = %SendMessageRequest{
      message: %Message{message_id: "m1", role: :user, task_id: "e2e-1", parts: [Part.text("hi")]},
      configuration: %SendMessageConfiguration{task_push_notification_config: cfg}
    }

    {:ok, _task} = DefaultHandler.send_message(server, req)

    bodies = collect_bodies([])
    frames = Enum.map(bodies, &A2A.JSON.decode!(&1, A2A.Types.StreamResponse))

    assert Enum.any?(
             frames,
             &match?(%{kind: :status_update, status_update: %{status: %{state: :completed}}}, &1)
           )
  end

  defp collect_bodies(acc) do
    receive do
      {:webhook, _headers, body} -> collect_bodies([body | acc])
    after
      1_000 -> Enum.reverse(acc)
    end
  end
end
