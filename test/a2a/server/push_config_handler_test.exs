defmodule A2A.Server.PushConfigHandlerTest do
  use ExUnit.Case, async: false
  alias A2A.Server.{DefaultHandler, PushConfigStore}

  alias A2A.Types.{
    DeleteTaskPushNotificationConfigRequest,
    GetTaskPushNotificationConfigRequest,
    ListTaskPushNotificationConfigsRequest,
    TaskPushNotificationConfig
  }

  defp start(opts) do
    name = :"srv_pc_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_pc_#{System.unique_integer([:positive])}"
    base = [name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub]
    start_supervised!({A2A.Server.Supervisor, base ++ opts})
    if opts[:push_notifications], do: :ets.delete_all_objects(PushConfigStore.ETS)
    A2A.Server.handle(name)
  end

  test "disabled server returns push_notification_not_supported" do
    server = start([])

    assert {:error, %A2A.Error{code: :push_notification_not_supported}} =
             DefaultHandler.create_push_config(server, %TaskPushNotificationConfig{
               task_id: "t1",
               url: "https://h/cb"
             })
  end

  test "create assigns an id, get/list/delete round-trip" do
    server = start(push_notifications: true)

    {:ok, stored} =
      DefaultHandler.create_push_config(server, %TaskPushNotificationConfig{
        task_id: "t1",
        url: "https://h/cb"
      })

    assert is_binary(stored.id) and stored.id != ""

    assert {:ok, ^stored} =
             DefaultHandler.get_push_config(server, %GetTaskPushNotificationConfigRequest{
               task_id: "t1",
               id: stored.id
             })

    {:ok, list} =
      DefaultHandler.list_push_configs(server, %ListTaskPushNotificationConfigsRequest{
        task_id: "t1"
      })

    assert length(list.configs) == 1

    assert {:ok, :deleted} =
             DefaultHandler.delete_push_config(server, %DeleteTaskPushNotificationConfigRequest{
               task_id: "t1",
               id: stored.id
             })

    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.get_push_config(server, %GetTaskPushNotificationConfigRequest{
               task_id: "t1",
               id: stored.id
             })
  end

  test "create rejects a non-http url via the default validator" do
    server = start(push_notifications: true)

    assert {:error, %A2A.Error{code: :invalid_params}} =
             DefaultHandler.create_push_config(server, %TaskPushNotificationConfig{
               task_id: "t1",
               url: "ftp://nope"
             })
  end
end
