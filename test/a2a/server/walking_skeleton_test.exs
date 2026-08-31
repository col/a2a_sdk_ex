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
    # Task ids are server-generated (spec 3.4.2), so the id to read back comes
    # from the returned task rather than from the request.
    req = %SendMessageRequest{
      message: %Message{message_id: "m2", role: :user, parts: [Part.text("yo")]}
    }

    {:ok, %Task{id: id}} = DefaultHandler.send_message(server, req)

    assert {:ok, %Task{id: ^id, status: %{state: :completed}}} =
             DefaultHandler.get_task(server, %GetTaskRequest{id: id})
  end

  test "continuing a terminal task is rejected", %{server: server} do
    req = %SendMessageRequest{
      message: %Message{message_id: "m3", role: :user, parts: [Part.text("x")]}
    }

    {:ok, %Task{id: id}} = DefaultHandler.send_message(server, req)

    again = %SendMessageRequest{
      message: %Message{message_id: "m4", role: :user, task_id: id, parts: [Part.text("x")]}
    }

    assert {:error, %A2A.Error{code: :task_not_continuable}} =
             DefaultHandler.send_message(server, again)
  end

  test "a message naming a task that does not exist is rejected", %{server: server} do
    # Spec 3.4.2: a client-supplied taskId MUST reference an existing task, and
    # client-provided ids for *creating* tasks are not supported — so this is
    # TaskNotFound, not an implicit create.
    req = %SendMessageRequest{
      message: %Message{message_id: "m5", role: :user, task_id: "ghost", parts: [Part.text("x")]}
    }

    assert {:error, %A2A.Error{code: :task_not_found}} = DefaultHandler.send_message(server, req)
  end

  test "get_task on an unknown id returns not_found", %{server: server} do
    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.get_task(server, %GetTaskRequest{id: "nope"})
  end
end
