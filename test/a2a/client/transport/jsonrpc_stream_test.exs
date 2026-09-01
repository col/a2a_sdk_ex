defmodule A2A.Client.Transport.JSONRPCStreamTest do
  use ExUnit.Case, async: true
  alias A2A.Client.{Config, HTTP.Stub}
  alias A2A.Client.Transport.JSONRPC

  alias A2A.Types.{
    Message,
    Part,
    SendMessageRequest,
    StreamResponse,
    Task,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  defp client, do: %A2A.Client{endpoint: "http://x/", config: Config.new(http_client: Stub)}

  defp frame(sr) do
    "data: " <>
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "result" => A2A.JSON.to_json_map(sr)}) <>
      "\n\n"
  end

  test "yields decoded event structs to terminal" do
    task = %Task{id: "t1", context_id: "c1", status: %TaskStatus{state: :submitted}}

    upd = %TaskStatusUpdateEvent{
      task_id: "t1",
      context_id: "c1",
      status: %TaskStatus{state: :completed}
    }

    chunks = [frame(StreamResponse.task(task)), frame(StreamResponse.status_update(upd))]

    Stub.put(%{
      {:post, "/"} => %{status: 200, headers: [{"content-type", "text/event-stream"}], body: chunks}
    })

    msg = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    {:ok, stream} = JSONRPC.send_message_stream(client(), %SendMessageRequest{message: msg}, [])
    events = Enum.to_list(stream)
    assert [%Task{id: "t1"}, %TaskStatusUpdateEvent{task_id: "t1"}] = events
  end

  test "an error frame raises A2A.Error on enumeration" do
    err_frame =
      "data: " <>
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"code" => -32_001, "message" => "gone"}
        }) <> "\n\n"

    Stub.put(%{{:post, "/"} => %{status: 200, headers: [], body: [err_frame]}})
    msg = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    {:ok, stream} = JSONRPC.send_message_stream(client(), %SendMessageRequest{message: msg}, [])
    assert_raise A2A.Error, fn -> Enum.to_list(stream) end
  end
end
