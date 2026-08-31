defmodule A2A.Plug.RESTPushTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.Router
  alias A2A.Server.PushConfigStore

  # NOTE: `A2A.Server.TaskStore.ETS` is globally named (see CLAUDE.md "Known
  # constraints"), so only one `A2A.Server.Supervisor` tree may run at a time
  # in this test process. Each test starts its own tree inline (instead of a
  # shared `setup` block) so `start_supervised!`'s automatic teardown fully
  # unwinds the previous tree before the next test starts its own.
  defp start_enabled_server! do
    name = :"srv_restpush_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_restpush_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor,
       name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub, push_notifications: true}
    )

    :ets.delete_all_objects(PushConfigStore.ETS)
    Router.init(server: name)
  end

  defp req(method, path, body \\ nil) do
    conn = conn(method, path, body)
    if body, do: put_req_header(conn, "content-type", "application/a2a+json"), else: conn
  end

  test "POST creates, GET reads, GET lists, DELETE removes" do
    opts = start_enabled_server!()
    body = Jason.encode!(%{"taskId" => "t1", "url" => "https://h/cb"})
    conn = Router.call(req(:post, "/tasks/t1/pushNotificationConfigs", body), opts)
    assert conn.status == 200
    id = Jason.decode!(conn.resp_body)["id"]
    assert is_binary(id)

    conn = Router.call(req(:get, "/tasks/t1/pushNotificationConfigs/#{id}"), opts)
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["url"] == "https://h/cb"

    conn = Router.call(req(:get, "/tasks/t1/pushNotificationConfigs"), opts)
    assert conn.status == 200
    assert length(Jason.decode!(conn.resp_body)["configs"]) == 1

    conn = Router.call(req(:delete, "/tasks/t1/pushNotificationConfigs/#{id}"), opts)
    assert conn.status == 200
  end

  test "disabled server → 400 PUSH_NOTIFICATION_NOT_SUPPORTED" do
    name = :"srv_restoff_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_restoff_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    opts = Router.init(server: name)

    body = Jason.encode!(%{"taskId" => "t1", "url" => "https://h/cb"})
    conn = Router.call(req(:post, "/tasks/t1/pushNotificationConfigs", body), opts)
    assert conn.status == 400

    assert Jason.decode!(conn.resp_body)["details"] |> hd() |> Map.get("reason") ==
             "PUSH_NOTIFICATION_NOT_SUPPORTED"
  end
end
