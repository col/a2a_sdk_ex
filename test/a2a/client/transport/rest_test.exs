defmodule A2A.Client.Transport.RESTTest do
  use ExUnit.Case, async: true
  alias A2A.Client.{Config, HTTP.Stub}
  alias A2A.Client.Transport.REST

  alias A2A.Types.{
    CancelTaskRequest,
    GetTaskRequest,
    Message,
    Part,
    SendMessageRequest,
    Task,
    TaskStatus
  }

  defp client, do: %A2A.Client{endpoint: "http://x", config: Config.new(http_client: Stub)}
  defp json(map), do: %{status: 200, headers: [], body: Jason.encode!(map)}

  test "send_message POSTs /message:send and returns Task" do
    task = %Task{id: "t1", context_id: "c1", status: %TaskStatus{state: :completed}}
    Stub.put(%{{:post, "/message:send"} => json(%{"task" => A2A.JSON.to_json_map(task)})})
    msg = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}

    assert {:ok, %Task{id: "t1"}} =
             REST.send_message(client(), %SendMessageRequest{message: msg}, [])
  end

  test "get_task GETs /tasks/{id} and passes historyLength" do
    Stub.put(%{
      {:get, "/tasks/t1"} => fn req ->
        assert req.url =~ "historyLength=5"

        {:ok,
         json(%{
           "id" => "t1",
           "contextId" => "c1",
           "status" => %{"state" => "TASK_STATE_COMPLETED"}
         })}
      end
    })

    assert {:ok, %Task{id: "t1"}} =
             REST.get_task(client(), %GetTaskRequest{id: "t1", history_length: 5}, [])
  end

  test "cancel_task POSTs /tasks/{id}:cancel" do
    Stub.put(%{
      {:post, "/tasks/t1:cancel"} =>
        json(%{"id" => "t1", "contextId" => "c1", "status" => %{"state" => "TASK_STATE_CANCELED"}})
    })

    assert {:ok, %Task{}} = REST.cancel_task(client(), %CancelTaskRequest{id: "t1"}, [])
  end

  test "non-2xx decodes AIP-193 error" do
    body = %{
      "error" => %{
        "code" => 404,
        "status" => "NOT_FOUND",
        "message" => "task not found: t9",
        "details" => [%{"reason" => "TASK_NOT_FOUND"}]
      }
    }

    Stub.put(%{{:get, "/tasks/t9"} => %{status: 404, headers: [], body: Jason.encode!(body)}})

    assert {:error, %A2A.Error{code: :task_not_found}} =
             REST.get_task(client(), %GetTaskRequest{id: "t9"}, [])
  end
end
