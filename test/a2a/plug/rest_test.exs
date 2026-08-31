defmodule A2A.Plug.RESTTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.Router
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Server.TaskStore.ETS, as: TaskStoreETS
  alias A2A.Types.{AgentCard, Message, Part}

  @card %AgentCard{name: "Echo", version: "0.1.0", default_input_modes: ["text/plain"]}

  setup do
    name = :"srv_rest_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_rest_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor,
       name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub, agent_card: @card}
    )

    :ets.delete_all_objects(TaskStoreETS)
    %{opts: Router.init(server: name), name: name}
  end

  defp call(conn, opts), do: Router.call(conn, opts)

  defp create_task(opts) do
    body = %{
      "message" =>
        A2A.JSON.to_json_map(%Message{
          message_id: "seed-m1",
          role: :user,
          parts: [Part.text("hi")]
        })
    }

    conn =
      conn(:post, "/message:send", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> call(opts)

    %{"task" => %{"id" => id}} = Jason.decode!(conn.resp_body)
    id
  end

  test "GET /tasks/:id returns a task as application/a2a+json for a known id", %{opts: opts} do
    id = create_task(opts)

    conn = call(conn(:get, "/tasks/#{id}"), opts)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/a2a+json"
    assert Jason.decode!(conn.resp_body)["id"] == id
  end

  test "GET /tasks/:id unknown -> 404 google.rpc.Status body", %{opts: opts} do
    conn = call(conn(:get, "/tasks/nope"), opts)
    assert conn.status == 404
    body = Jason.decode!(conn.resp_body)
    assert body["code"] == 5
    assert [%{"reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org"}] = body["details"]
  end

  test "POST /message:send returns a SendMessageResponse", %{opts: opts} do
    body =
      Jason.encode!(%{
        "message" =>
          A2A.JSON.to_json_map(%Message{
            message_id: "m1",
            role: :user,
            parts: [Part.text("hi")]
          })
      })

    conn =
      conn(:post, "/message:send", body)
      |> put_req_header("content-type", "application/json")
      |> call(opts)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) |> is_map()
  end

  test "GET /tasks lists tasks", %{opts: opts} do
    _id = create_task(opts)

    conn = call(conn(:get, "/tasks"), opts)
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["tasks"] |> is_list()
  end

  test "POST /tasks/:id:cancel unknown -> 404", %{opts: opts} do
    conn =
      conn(:post, "/tasks/nope:cancel", "{}")
      |> put_req_header("content-type", "application/json")
      |> call(opts)

    assert conn.status == 404
  end

  test "GET /tasks/:id:subscribe streams SSE with bare StreamResponse frames", %{opts: opts} do
    id = create_task(opts)

    conn = call(conn(:get, "/tasks/#{id}:subscribe"), opts)
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/event-stream"
    refute conn.resp_body =~ "jsonrpc"
  end
end
