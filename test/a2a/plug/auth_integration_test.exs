defmodule A2A.Plug.AuthIntegrationTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.Router
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Server.TaskStore.ETS, as: TaskStoreETS
  alias A2A.Types.AgentCard
  alias A2A.User

  @card %AgentCard{name: "Echo", version: "0.1.0", default_input_modes: ["text/plain"]}

  setup do
    name = :"srv_authint_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_authint_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor,
       name: name,
       executor: A2A.Test.EchoExecutor,
       pubsub: pubsub,
       agent_card: @card,
       user_resolver: fn conn ->
         case get_req_header(conn, "x-user") do
           [id | _] -> %User{id: id, authenticated?: true}
           [] -> User.anonymous()
         end
       end,
       owner_resolver: fn %User{id: id} -> id end}
    )

    :ets.delete_all_objects(TaskStoreETS)
    %{opts: Router.init(server: name)}
  end

  defp rpc(opts, method, params, user) do
    body = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})

    conn(:post, "/", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-user", user)
    |> Router.call(opts)
    |> then(& &1.resp_body)
    |> Jason.decode!()
  end

  test "a task created by one user is TaskNotFound for another", %{opts: opts} do
    send =
      rpc(
        opts,
        "SendMessage",
        %{"message" => %{"messageId" => "m-alice", "parts" => [%{"text" => "hi"}]}},
        "alice"
      )

    task_id = get_in(send, ["result", "task", "id"])
    assert is_binary(task_id)

    ok = rpc(opts, "GetTask", %{"id" => task_id}, "alice")
    assert get_in(ok, ["result", "id"]) == task_id

    denied = rpc(opts, "GetTask", %{"id" => task_id}, "bob")
    assert get_in(denied, ["error", "code"]) == -32_001
  end
end
