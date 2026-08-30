defmodule A2A.Server.StreamingTest do
  use ExUnit.Case, async: false
  alias A2A.Server.DefaultHandler
  alias A2A.Types.{Message, Part, SendMessageRequest}

  setup do
    name = :"srv_stream_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_stream_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{server: A2A.Server.handle(name)}
  end

  defp req(text, opts \\ []) do
    %SendMessageRequest{
      message: %Message{
        message_id: "m_#{System.unique_integer([:positive])}",
        role: :user,
        task_id: Keyword.get(opts, :task_id),
        parts: [Part.text(text)]
      }
    }
  end

  test "blocking send_message still runs to completion on the reshaped path",
       %{server: server} do
    assert {:ok, %A2A.Types.Task{status: %{state: :completed}}} =
             DefaultHandler.send_message(server, req("hi"))
  end

  test "a finite per-request drain_timeout on a silent task yields :timeout",
       %{server: server} do
    # SilentExecutor never emits and never returns quickly; the idle timeout fires.
    server = %{server | executor: A2A.Test.SilentExecutor}

    assert {:error, %A2A.Error{code: :timeout}} =
             DefaultHandler.send_message(server, req("x"), drain_timeout: 50)
  end

  test "send_message_stream yields ordered StreamResponse frames ending in completed",
       %{server: server} do
    frames = server |> DefaultHandler.send_message_stream(req("hi")) |> Enum.to_list()

    assert Enum.all?(frames, &match?(%A2A.Types.StreamResponse{}, &1))
    # EchoExecutor: start_work (working status) → add_artifact → complete
    assert Enum.any?(frames, &match?(%A2A.Types.StreamResponse{kind: :status_update}, &1))
    assert Enum.any?(frames, &match?(%A2A.Types.StreamResponse{kind: :artifact_update}, &1))

    last = List.last(frames)

    assert %A2A.Types.StreamResponse{
             kind: :status_update,
             status_update: %{status: %{state: :completed}}
           } =
             last
  end

  test "every streamed frame round-trips through A2A.JSON", %{server: server} do
    frames = server |> DefaultHandler.send_message_stream(req("hi")) |> Enum.to_list()

    for frame <- frames do
      json = A2A.JSON.encode!(frame)
      assert {:ok, %A2A.Types.StreamResponse{}} = A2A.JSON.decode(json, A2A.Types.StreamResponse)
    end
  end

  test "streaming does not stop on auth_required but stops on input_required",
       %{server: server} do
    server = %{server | executor: A2A.Test.AuthThenInputExecutor}
    frames = server |> DefaultHandler.send_message_stream(req("go")) |> Enum.to_list()

    states =
      for %A2A.Types.StreamResponse{kind: :status_update, status_update: %{status: %{state: s}}} <-
            frames,
          do: s

    assert :auth_required in states
    assert List.last(states) == :input_required
  end
end
