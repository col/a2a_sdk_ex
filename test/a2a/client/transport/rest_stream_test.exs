defmodule A2A.Client.Transport.RESTStreamTest do
  use ExUnit.Case, async: true
  alias A2A.Client.{Config, HTTP.Stub}
  alias A2A.Client.Transport.REST

  alias A2A.Types.{
    Message,
    Part,
    SendMessageRequest,
    StreamResponse,
    SubscribeToTaskRequest,
    Task,
    TaskStatus
  }

  defp client, do: %A2A.Client{endpoint: "http://x", config: Config.new(http_client: Stub)}
  defp frame(sr), do: "data: " <> Jason.encode!(A2A.JSON.to_json_map(sr)) <> "\n\n"

  test "send_message_stream yields decoded events" do
    task = %Task{id: "t1", context_id: "c1", status: %TaskStatus{state: :submitted}}

    Stub.put(%{
      {:post, "/message:stream"} => %{
        status: 200,
        headers: [],
        body: [frame(StreamResponse.task(task))]
      }
    })

    msg = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    {:ok, stream} = REST.send_message_stream(client(), %SendMessageRequest{message: msg}, [])
    assert [%Task{id: "t1"}] = Enum.to_list(stream)
  end

  test "resubscribe POSTs /tasks/{id}:subscribe" do
    task = %Task{id: "t1", context_id: "c1", status: %TaskStatus{state: :working}}

    Stub.put(%{
      {:post, "/tasks/t1:subscribe"} => %{
        status: 200,
        headers: [],
        body: [frame(StreamResponse.task(task))]
      }
    })

    {:ok, stream} = REST.resubscribe(client(), %SubscribeToTaskRequest{id: "t1"}, [])
    assert [%Task{id: "t1"}] = Enum.to_list(stream)
  end
end
