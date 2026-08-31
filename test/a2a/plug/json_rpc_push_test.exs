defmodule A2A.Plug.JSONRPCPushTest do
  use ExUnit.Case, async: false
  alias A2A.Plug.JSONRPC
  alias A2A.Server.PushConfigStore

  setup do
    name = :"srv_rpcpush_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_rpcpush_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor,
       name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub, push_notifications: true}
    )

    :ets.delete_all_objects(PushConfigStore.ETS)
    %{server: A2A.Server.handle(name)}
  end

  defp call(server, method, params) do
    JSONRPC.dispatch(server, %{method: method, params: params, id: 1})
  end

  test "set → get → list → delete round-trip over JSON-RPC", %{server: server} do
    {:reply, set_env} =
      call(server, "tasks/pushNotificationConfig/set", %{
        "taskId" => "t1",
        "url" => "https://h/cb"
      })

    id = set_env["result"]["id"]
    assert is_binary(id) and id != ""

    assert {:reply, get_env} =
             call(server, "tasks/pushNotificationConfig/get", %{"taskId" => "t1", "id" => id})

    assert get_env["result"]["url"] == "https://h/cb"

    assert {:reply, list_env} =
             call(server, "tasks/pushNotificationConfig/list", %{"taskId" => "t1"})

    assert length(list_env["result"]["configs"]) == 1

    assert {:reply, del_env} =
             call(server, "tasks/pushNotificationConfig/delete", %{"taskId" => "t1", "id" => id})

    assert del_env["result"] == nil
  end

  test "disabled server surfaces PUSH_NOTIFICATION_NOT_SUPPORTED", %{server: server} do
    # Per CLAUDE.md: TaskStore.ETS/PushConfigStore.ETS are globally named, so a
    # second A2A.Server.Supervisor tree can't run alongside the setup's. Reuse
    # the setup server and override the push fields instead.
    disabled = %{server | push_notifications: false, push_store: nil}

    assert {:error, env} =
             call(disabled, "tasks/pushNotificationConfig/set", %{
               "taskId" => "t1",
               "url" => "https://h/cb"
             })

    assert env["error"]["code"] == -32_003
  end
end
