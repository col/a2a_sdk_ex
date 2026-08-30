defmodule A2A.Plug.SSETest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.Router
  alias A2A.Server.TaskStore
  alias A2A.Test.EchoExecutor
  alias A2A.Types.{Message, Part, SendMessageRequest, SubscribeToTaskRequest}

  setup do
    name = :"srv_sse_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_sse_#{System.unique_integer([:positive])}"

    start_supervised!({A2A.Server.Supervisor, name: name, executor: EchoExecutor, pubsub: pubsub})

    :ets.delete_all_objects(TaskStore.ETS)
    %{opts: Router.init(server: name)}
  end

  # Parse SSE body into the list of decoded `result` maps.
  defp sse_events(body) do
    body
    |> String.split("\n\n", trim: true)
    |> Enum.map(fn line ->
      "data: " <> json = String.trim(line)
      Jason.decode!(json)
    end)
  end

  defp stream_post(opts, method, params_struct, id) do
    body =
      %{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => A2A.JSON.to_json_map(params_struct)
      }
      |> Jason.encode!()

    conn(:post, "/", body)
    |> put_req_header("content-type", "application/json")
    |> Router.call(opts)
  end

  test "message/stream yields ordered SSE frames ending in a terminal task", %{opts: opts} do
    req = %SendMessageRequest{
      message: %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    }

    conn = stream_post(opts, "message/stream", req, 5)

    assert conn.status == 200

    assert {"content-type", "text/event-stream" <> _} =
             Enum.find(conn.resp_headers, fn {k, _} -> k == "content-type" end)

    events = sse_events(conn.resp_body)
    assert events != []
    assert Enum.all?(events, &match?(%{"jsonrpc" => "2.0", "id" => 5, "result" => _}, &1))
    # The Echo executor completes; a terminal completed task appears among the frames.
    assert Enum.any?(events, fn e ->
             get_in(e, ["result", "task", "status", "state"]) == "TASK_STATE_COMPLETED" or
               get_in(e, ["result", "statusUpdate", "status", "state"]) == "TASK_STATE_COMPLETED"
           end)
  end

  test "resubscribe to an unknown task renders a JSON-RPC error, not a 200 stream", %{opts: opts} do
    req = %SubscribeToTaskRequest{id: "does-not-exist"}
    conn = stream_post(opts, "tasks/resubscribe", req, 6)

    assert conn.status == 200

    refute Enum.any?(conn.resp_headers, fn {k, v} ->
             k == "content-type" and String.starts_with?(v, "text/event-stream")
           end)

    assert %{"error" => %{"code" => -32_001}} = Jason.decode!(conn.resp_body)
  end

  test "respond/4 uses a custom frame formatter (bare frame, no envelope)" do
    frame =
      A2A.Types.StreamResponse.task(%A2A.Types.Task{
        id: "t",
        status: %A2A.Types.TaskStatus{state: :working}
      })

    formatter = fn _id, f -> Jason.encode_to_iodata!(A2A.JSON.to_json_map(f)) end

    conn =
      Plug.Test.conn(:get, "/")
      |> A2A.Plug.SSE.respond(nil, [frame], formatter)

    # Body is an SSE data frame carrying the BARE StreamResponse (no "jsonrpc"/"id").
    refute conn.resp_body =~ "jsonrpc"
    assert conn.resp_body =~ "data:"
  end
end
