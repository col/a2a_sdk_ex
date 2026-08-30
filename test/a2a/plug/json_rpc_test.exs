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
      "method" => "message/send",
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
        Jason.encode!(%{"jsonrpc" => "2.0", "id" => 7, "method" => "tasks/cancel", "params" => %{}})
      )

    assert {:error, %{"id" => 7, "error" => %{"code" => -32_601}}} = JSONRPC.dispatch(server, env)
  end

  test "bad params -> -32602", %{server: server} do
    {:ok, env} =
      JSONRPC.decode_envelope(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 8,
          "method" => "message/send",
          "params" => %{"message" => %{"parts" => "notalist"}}
        })
      )

    assert {:error, %{"id" => 8, "error" => %{"code" => -32_602}}} = JSONRPC.dispatch(server, env)
  end

  test "message/send happy path -> {:reply, result with a task}", %{server: server} do
    {:ok, env} = JSONRPC.decode_envelope(send_body("hi"))
    assert {:reply, %{"id" => 1, "result" => result}} = JSONRPC.dispatch(server, env)
    # SendMessageResponse proto3-JSON: a task with a completed status.
    assert %{"task" => %{"status" => %{"state" => "TASK_STATE_COMPLETED"}}} = result
  end

  test "tasks/get unknown id -> -32001", %{server: server} do
    {:ok, env} =
      JSONRPC.decode_envelope(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tasks/get",
          "params" => %{"id" => "nope"}
        })
      )

    assert {:error, %{"id" => 3, "error" => %{"code" => -32_001}}} = JSONRPC.dispatch(server, env)
  end

  test "message/stream -> {:stream, id, enumerable}", %{server: server} do
    body =
      %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "message/stream",
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
end
