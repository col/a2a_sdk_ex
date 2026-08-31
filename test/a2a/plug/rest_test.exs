defmodule A2A.Plug.RESTTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.Router
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Server.TaskStore.ETS, as: TaskStoreETS
  alias A2A.Types.{AgentCard, Message, Part}

  @card %AgentCard{name: "Echo", version: "0.1.0", default_input_modes: ["text/plain"]}

  # `@tag executor: SomeExecutor` swaps the agent for one test. The router
  # resolves the server by name per request, so the executor cannot be overridden
  # per call the way handler tests do it — and the globally-named TaskStore.ETS
  # rules out running a second tree alongside this one.
  setup context do
    name = :"srv_rest_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_rest_#{System.unique_integer([:positive])}"
    executor = Map.get(context, :executor, A2A.Test.EchoExecutor)

    start_supervised!(
      {ServerSupervisor, name: name, executor: executor, pubsub: pubsub, agent_card: @card}
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

  # Spec 11.1: "Content-Type: application/json for requests and responses". The
  # registered application/a2a+json media type (14.1.1) is not what the binding
  # section mandates, and a client matching on "application/json" never sees it.
  test "GET /tasks/:id returns a task as application/json for a known id", %{opts: opts} do
    id = create_task(opts)

    conn = call(conn(:get, "/tasks/#{id}"), opts)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    assert Jason.decode!(conn.resp_body)["id"] == id
  end

  test "GET /tasks/:id honours the historyLength query parameter", %{opts: opts} do
    # Spec 11.5: GET has no body, so request parameters arrive as camelCase query
    # parameters — `?historyLength=0` must cap the response the same way the
    # JSON-RPC request field does.
    id = create_task(opts)

    assert %{"history" => [_ | _]} = Jason.decode!(call(conn(:get, "/tasks/#{id}"), opts).resp_body)

    body = Jason.decode!(call(conn(:get, "/tasks/#{id}?historyLength=0"), opts).resp_body)
    refute Map.has_key?(body, "history")
  end

  test "GET /tasks/:id unknown -> 404 AIP-193 error body", %{opts: opts} do
    conn = call(conn(:get, "/tasks/nope"), opts)

    assert conn.status == 404
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

    assert %{"error" => error} = Jason.decode!(conn.resp_body)
    assert error["code"] == 404
    assert error["status"] == "NOT_FOUND"
    assert [%{"reason" => "TASK_NOT_FOUND", "domain" => "a2a-protocol.org"}] = error["details"]
  end

  test "a malformed body is rendered as an AIP-193 error too", %{opts: opts} do
    conn =
      conn(:post, "/message:send", ~s({"message": {"role": "NOPE"}}))
      |> put_req_header("content-type", "application/json")
      |> call(opts)

    assert conn.status == 400

    assert %{"error" => %{"code" => 400, "status" => "INVALID_ARGUMENT"}} =
             Jason.decode!(conn.resp_body)
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

  @tag executor: A2A.Test.ReplyExecutor
  test "POST /message:send renders a direct Message reply", %{opts: opts} do
    body =
      Jason.encode!(%{
        "message" =>
          A2A.JSON.to_json_map(%Message{
            message_id: "m_reply",
            role: :user,
            parts: [Part.text("ping")]
          })
      })

    conn =
      conn(:post, "/message:send", body)
      |> put_req_header("content-type", "application/json")
      |> call(opts)

    assert conn.status == 200
    decoded = Jason.decode!(conn.resp_body)
    assert %{"message" => %{"parts" => [%{"text" => "direct reply"}]}} = decoded
    refute Map.has_key?(decoded, "task")
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

  test "POST /message:stream streams SSE with bare StreamResponse frames", %{opts: opts} do
    body =
      Jason.encode!(%{
        "message" =>
          A2A.JSON.to_json_map(%Message{
            message_id: "m_stream",
            role: :user,
            parts: [Part.text("hi")]
          })
      })

    conn =
      conn(:post, "/message:stream", body)
      |> put_req_header("content-type", "application/json")
      |> call(opts)

    assert get_resp_header(conn, "content-type") |> hd() =~ "text/event-stream"
    refute conn.resp_body =~ "jsonrpc"
  end

  # Spec 11.3.2 lists `POST /tasks/{id}:subscribe`; the vendored proto annotates
  # the same operation `get:`. The two disagree, so both verbs are served.
  @tag executor: A2A.Test.AuthThenInputExecutor
  test "POST /tasks/:id:subscribe subscribes like the GET form", %{opts: opts} do
    # A task left in `input_required` is non-terminal, so subscribing is valid.
    id = create_task(opts)

    conn =
      conn(:post, "/tasks/#{id}:subscribe")
      |> put_req_header("content-type", "application/json")
      |> call(opts)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/event-stream"
    assert conn.resp_body =~ "TASK_STATE_INPUT_REQUIRED"
    refute conn.resp_body =~ "jsonrpc"
  end

  test "an unrouted path renders an AIP-193 404, not an empty body", %{opts: opts} do
    conn = call(conn(:get, "/nope"), opts)

    assert conn.status == 404
    assert %{"error" => %{"code" => 404, "status" => "NOT_FOUND"}} = Jason.decode!(conn.resp_body)
  end

  test "GET /tasks/:id:subscribe on a terminal task -> 400 UNSUPPORTED_OPERATION",
       %{opts: opts} do
    # Spec 3.1.6: subscribing to a task that has already reached a terminal state
    # is UnsupportedOperationError, not an empty stream.
    id = create_task(opts)

    conn = call(conn(:get, "/tasks/#{id}:subscribe"), opts)

    assert conn.status == 400
    assert %{"error" => %{"details" => [detail]}} = Jason.decode!(conn.resp_body)
    assert detail["reason"] == "UNSUPPORTED_OPERATION"
  end
end
