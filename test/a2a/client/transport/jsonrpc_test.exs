defmodule A2A.Client.Transport.JSONRPCTest do
  use ExUnit.Case, async: true
  alias A2A.Client.{Config, HTTP.Stub}
  alias A2A.Client.Transport.JSONRPC
  alias A2A.Types.{GetTaskRequest, Message, Part, SendMessageRequest, Task, TaskStatus}

  defp client, do: %A2A.Client{endpoint: "http://x/", config: Config.new(http_client: Stub)}

  defp rpc_ok(result),
    do: %{
      status: 200,
      headers: [],
      body: Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "result" => result})
    }

  defp rpc_err(obj),
    do: %{
      status: 200,
      headers: [],
      body: Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "error" => obj})
    }

  test "send_message returns a Task" do
    task = %Task{id: "t1", context_id: "c1", status: %TaskStatus{state: :completed}}
    Stub.put(%{{:post, "/"} => rpc_ok(%{"task" => A2A.JSON.to_json_map(task)})})
    msg = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}

    assert {:ok, %Task{id: "t1"}} =
             JSONRPC.send_message(client(), %SendMessageRequest{message: msg}, [])
  end

  test "send_message returns a bare Message" do
    message = %Message{message_id: "m2", role: :agent, parts: [Part.text("yo")]}
    Stub.put(%{{:post, "/"} => rpc_ok(%{"message" => A2A.JSON.to_json_map(message)})})
    msg = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}

    assert {:ok, %Message{message_id: "m2"}} =
             JSONRPC.send_message(client(), %SendMessageRequest{message: msg}, [])
  end

  test "error object decodes to A2A.Error" do
    Stub.put(%{{:post, "/"} => rpc_err(%{"code" => -32_001, "message" => "task not found: t9"})})

    assert {:error, %A2A.Error{code: :task_not_found}} =
             JSONRPC.get_task(client(), %GetTaskRequest{id: "t9"}, [])
  end

  test "sends correct method + params body" do
    Stub.put(%{
      {:post, "/"} => fn req ->
        assert %{"method" => "GetTask", "params" => %{"id" => "t1"}} = Jason.decode!(req.body)

        {:ok,
         rpc_ok(%{
           "id" => "t1",
           "contextId" => "c1",
           "status" => %{"state" => "TASK_STATE_COMPLETED"}
         })}
      end
    })

    assert {:ok, %Task{id: "t1"}} = JSONRPC.get_task(client(), %GetTaskRequest{id: "t1"}, [])
  end
end
