defmodule A2A.Plug.JSONRPCTest do
  use ExUnit.Case, async: false

  alias A2A.Plug.JSONRPC
  alias A2A.Types.{Message, Part, SendMessageRequest}

  setup do
    name = :"srv_rpc_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_rpc_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{server: A2A.Server.handle(name)}
  end

  defp send_body(text) do
    req = %SendMessageRequest{
      message: %Message{message_id: "m1", role: :user, parts: [Part.text(text)]}
    }

    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "SendMessage",
      "params" => A2A.JSON.to_json_map(req)
    }
    |> Jason.encode!()
  end

  test "malformed JSON -> -32700", %{server: _server} do
    assert {:error, %{"error" => %{"code" => -32_700}}} = JSONRPC.decode_envelope("{bad")
  end

  test "non-request object -> -32600" do
    assert {:error, %{"error" => %{"code" => -32_600}}} =
             JSONRPC.decode_envelope(Jason.encode!(%{"foo" => 1}))

    assert {:error, %{"error" => %{"code" => -32_600}}} =
             JSONRPC.decode_envelope(Jason.encode!([1, 2, 3]))
  end

  test "unknown method -> -32601", %{server: server} do
    {:ok, env} =
      JSONRPC.decode_envelope(
        Jason.encode!(%{"jsonrpc" => "2.0", "id" => 7, "method" => "tasks/bogus", "params" => %{}})
      )

    assert {:error, %{"id" => 7, "error" => %{"code" => -32_601}}} = JSONRPC.dispatch(server, env)
  end

  test "bad params -> -32602", %{server: server} do
    {:ok, env} =
      JSONRPC.decode_envelope(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 8,
          "method" => "SendMessage",
          "params" => %{"message" => %{"parts" => "notalist"}}
        })
      )

    assert {:error, %{"id" => 8, "error" => %{"code" => -32_602}}} = JSONRPC.dispatch(server, env)
  end

  test "non-object params -> -32602", %{server: server} do
    {:ok, env} =
      JSONRPC.decode_envelope(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 9,
          "method" => "SendMessage",
          "params" => [1, 2]
        })
      )

    assert {:error, %{"id" => 9, "error" => %{"code" => -32_602}}} = JSONRPC.dispatch(server, env)
  end

  test "SendMessage happy path -> {:reply, result with a task}", %{server: server} do
    {:ok, env} = JSONRPC.decode_envelope(send_body("hi"))
    assert {:reply, %{"id" => 1, "result" => result}} = JSONRPC.dispatch(server, env)
    # SendMessageResponse proto3-JSON: a task with a completed status.
    assert %{"task" => %{"status" => %{"state" => "TASK_STATE_COMPLETED"}}} = result
  end

  test "GetTask unknown id -> -32001", %{server: server} do
    {:ok, env} =
      JSONRPC.decode_envelope(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "GetTask",
          "params" => %{"id" => "nope"}
        })
      )

    assert {:error, %{"id" => 3, "error" => %{"code" => -32_001}}} = JSONRPC.dispatch(server, env)
  end

  test "SendStreamingMessage -> {:stream, id, enumerable}", %{server: server} do
    body =
      %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "SendStreamingMessage",
        "params" =>
          A2A.JSON.to_json_map(%SendMessageRequest{
            message: %Message{message_id: "m2", role: :user, parts: [Part.text("yo")]}
          })
      }
      |> Jason.encode!()

    {:ok, env} = JSONRPC.decode_envelope(body)
    assert {:stream, 5, enum} = JSONRPC.dispatch(server, env)
    # Enumerate in THIS process (the caller) per the streaming contract.
    frames = Enum.to_list(enum)
    assert Enum.any?(frames, &match?(%A2A.Types.StreamResponse{}, &1))
  end

  test "CancelTask dispatches and renders the task", %{server: server} do
    env = %{method: "CancelTask", params: %{"id" => "missing"}, id: 1}
    assert {:error, %{"error" => %{"code" => -32_001}}} = JSONRPC.dispatch(server, env)
  end

  test "ListTasks dispatches and renders a ListTasksResponse", %{server: server} do
    {:ok, send_env} = JSONRPC.decode_envelope(send_body("hi"))
    assert {:reply, _} = JSONRPC.dispatch(server, send_env)

    env = %{method: "ListTasks", params: %{}, id: 2}
    assert {:reply, %{"result" => result}} = JSONRPC.dispatch(server, env)
    assert Map.has_key?(result, "tasks")
  end

  # A2A v1.0.0 spec section 5.3 (Method Mapping Reference) mandates PascalCase
  # JSON-RPC method names matching the gRPC method names. Params here are only
  # well-formed enough to reach the handler; each case asserts solely that the
  # method resolves in the dispatch table.
  @v1_methods [
    {"SendMessage", %{"message" => %{"messageId" => "m1", "parts" => [%{"text" => "hi"}]}}},
    {"SendStreamingMessage",
     %{"message" => %{"messageId" => "m1", "parts" => [%{"text" => "hi"}]}}},
    {"GetTask", %{"id" => "missing"}},
    {"ListTasks", %{}},
    {"CancelTask", %{"id" => "missing"}},
    {"SubscribeToTask", %{"id" => "missing"}},
    {"CreateTaskPushNotificationConfig", %{"taskId" => "t1"}},
    {"GetTaskPushNotificationConfig", %{"taskId" => "t1", "id" => "c1"}},
    {"ListTaskPushNotificationConfigs", %{"taskId" => "t1"}},
    {"DeleteTaskPushNotificationConfig", %{"taskId" => "t1", "id" => "c1"}}
  ]

  test "every v1.0 spec method name is dispatchable", %{server: server} do
    for {method, params} <- @v1_methods do
      result = JSONRPC.dispatch(server, %{method: method, params: params, id: 1})

      refute match?({:error, %{"error" => %{"code" => -32_601}}}, result),
             "#{method} is not in the dispatch table (got -32601 method not found)"
    end
  end

  test "pre-1.0 slash method names are no longer accepted", %{server: server} do
    for method <- ["message/send", "message/stream", "tasks/get", "tasks/list"] do
      assert {:error, %{"error" => %{"code" => -32_601}}} =
               JSONRPC.dispatch(server, %{method: method, params: %{}, id: 1})
    end
  end
end
