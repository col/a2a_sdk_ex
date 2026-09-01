defmodule A2A.Server.OwnershipTest do
  use ExUnit.Case, async: false

  alias A2A.Server
  alias A2A.Server.DefaultHandler
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Server.TaskStore.ETS, as: TaskStoreETS
  alias A2A.Server.PushConfigStore.ETS, as: PushStoreETS

  alias A2A.Types.{
    CancelTaskRequest,
    GetTaskRequest,
    ListTasksRequest,
    Message,
    Part,
    SendMessageRequest,
    TaskPushNotificationConfig
  }

  alias A2A.User

  @alice %User{id: "alice", authenticated?: true}
  @bob %User{id: "bob", authenticated?: true}

  setup do
    name = :"srv_owner_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_owner_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor,
       name: name,
       executor: A2A.Test.EchoExecutor,
       pubsub: pubsub,
       push_notifications: true,
       owner_resolver: fn %User{id: id} -> id end}
    )

    :ets.delete_all_objects(TaskStoreETS)
    :ets.delete_all_objects(PushStoreETS)
    %{server: Server.handle(name)}
  end

  defp as(server, user), do: Server.for_request(server, user)

  defp send_text(server, user, text) do
    req = %SendMessageRequest{message: %Message{role: :user, parts: [Part.text(text)]}}
    {:ok, task} = DefaultHandler.send_message(as(server, user), req)
    task
  end

  test "one owner cannot GetTask another owner's task", %{server: server} do
    task = send_text(server, @alice, "hi")

    assert {:ok, _} = DefaultHandler.get_task(as(server, @alice), %GetTaskRequest{id: task.id})

    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.get_task(as(server, @bob), %GetTaskRequest{id: task.id})
  end

  test "one owner cannot CancelTask another owner's task", %{server: server} do
    task = send_text(server, @alice, "hi")

    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.cancel_task(as(server, @bob), %CancelTaskRequest{id: task.id})
  end

  test "one owner cannot continue another owner's task via a taskId message", %{server: server} do
    task = send_text(server, @alice, "hi")

    req = %SendMessageRequest{
      message: %Message{role: :user, task_id: task.id, parts: [Part.text("again")]}
    }

    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.send_message(as(server, @bob), req)
  end

  test "ListTasks returns only the caller's tasks", %{server: server} do
    _a = send_text(server, @alice, "a")
    _b = send_text(server, @bob, "b")

    {:ok, alice_list} = DefaultHandler.list_tasks(as(server, @alice), %ListTasksRequest{})
    {:ok, bob_list} = DefaultHandler.list_tasks(as(server, @bob), %ListTasksRequest{})

    assert length(alice_list.tasks) == 1
    assert length(bob_list.tasks) == 1
    refute hd(alice_list.tasks).id == hd(bob_list.tasks).id
  end

  test "one owner cannot read another owner's push config", %{server: server} do
    task = send_text(server, @alice, "hi")

    cfg = %TaskPushNotificationConfig{
      task_id: task.id,
      id: "c1",
      url: "https://example.test/webhook"
    }

    {:ok, _} = DefaultHandler.create_push_config(as(server, @alice), cfg)

    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.get_push_config(
               as(server, @bob),
               %A2A.Types.GetTaskPushNotificationConfigRequest{
                 task_id: task.id,
                 id: "c1"
               }
             )
  end

  test "identical owner ids share storage (proves the key, not the caller, isolates)", %{
    server: server
  } do
    dup = %User{id: "same", authenticated?: true}
    task = send_text(server, dup, "hi")

    # A different User value that resolves to the SAME owner id sees the task.
    other = %User{id: "same", authenticated?: false}

    assert {:ok, _} =
             DefaultHandler.get_task(as(server, other), %GetTaskRequest{id: task.id})
  end
end
