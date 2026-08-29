defmodule A2A.Server.WalkingSkeletonTest do
  use ExUnit.Case, async: false
  alias A2A.Server.DefaultHandler
  alias A2A.Types.{GetTaskRequest, Message, Part, SendMessageRequest, Task}

  setup do
    name = :"srv_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{server: A2A.Server.handle(name)}
  end

  test "blocking send_message runs the echo agent to completion", %{server: server} do
    req = %SendMessageRequest{
      message: %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    }

    assert {:ok, %Task{status: %{state: :completed}} = task} =
             DefaultHandler.send_message(server, req)

    assert Enum.any?(task.artifacts, fn a -> Enum.any?(a.parts, &(&1.text == "echo: hi")) end)
  end

  test "get_task reads the completed task back from the store", %{server: server} do
    req = %SendMessageRequest{
      message: %Message{message_id: "m2", role: :user, task_id: "known", parts: [Part.text("yo")]}
    }

    {:ok, _} = DefaultHandler.send_message(server, req)

    assert {:ok, %Task{id: "known", status: %{state: :completed}}} =
             DefaultHandler.get_task(server, %GetTaskRequest{id: "known"})
  end

  test "continuing a terminal task is rejected", %{server: server} do
    req = %SendMessageRequest{
      message: %Message{message_id: "m3", role: :user, task_id: "term", parts: [Part.text("x")]}
    }

    {:ok, _} = DefaultHandler.send_message(server, req)

    again = %SendMessageRequest{
      message: %Message{message_id: "m4", role: :user, task_id: "term", parts: [Part.text("x")]}
    }

    assert {:error, %A2A.Error{code: :task_not_continuable}} =
             DefaultHandler.send_message(server, again)
  end

  test "get_task on an unknown id returns not_found", %{server: server} do
    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.get_task(server, %GetTaskRequest{id: "nope"})
  end
end
