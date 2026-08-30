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
end
