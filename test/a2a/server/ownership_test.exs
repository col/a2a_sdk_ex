defmodule A2A.Server.OwnershipTest do
  use ExUnit.Case, async: false

  alias A2A.Server
  alias A2A.Server.DefaultHandler
  alias A2A.Server.PushConfigStore.ETS, as: PushStoreETS
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Server.TaskStore.ETS, as: TaskStoreETS
  alias A2A.Test.GatedExecutor

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

    # Positive control: the task is VISIBLE to its owner. EchoExecutor completes
    # immediately, so cancel may return :task_not_cancelable — that still proves
    # visibility. The point is it must NOT be :task_not_found for alice.
    alice_result = DefaultHandler.cancel_task(as(server, @alice), %CancelTaskRequest{id: task.id})

    refute match?({:error, %A2A.Error{code: :task_not_found}}, alice_result)

    assert match?({:ok, %A2A.Types.Task{}}, alice_result) or
             match?({:error, %A2A.Error{code: :task_not_cancelable}}, alice_result),
           "expected alice's own cancel to be visible (ok or not_cancelable), got: #{inspect(alice_result)}"

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

    get_req = %A2A.Types.GetTaskPushNotificationConfigRequest{task_id: task.id, id: "c1"}

    # Positive control: the config actually persisted and is readable by its owner.
    assert {:ok, _} = DefaultHandler.get_push_config(as(server, @alice), get_req)

    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.get_push_config(as(server, @bob), get_req)
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

  test "one owner cannot CancelTask another owner's LIVE task", %{server: server} do
    # Regression for the security bug: cancel_task/2's live-execution branch used to
    # look up the execution Registry by task_id ALONE (owner-agnostic) and cancel it
    # without checking that the caller's owner scope can see the task. This proves
    # bob cannot cancel alice's in-flight task by id, while alice's own cancel still
    # succeeds.
    alice_server = %{as(server, @alice) | executor: GatedExecutor, id_generator: fn -> "live1" end}
    bob_server = %{as(server, @bob) | executor: GatedExecutor, id_generator: fn -> "live1" end}
    caller = self()

    spawn_link(fn ->
      req = %SendMessageRequest{message: %Message{role: :user, parts: [Part.text("go")]}}
      stream = DefaultHandler.send_message_stream(alice_server, req)
      send(caller, {:frames, Enum.to_list(stream)})
    end)

    wait_for_task(alice_server, "live1")

    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.cancel_task(bob_server, %CancelTaskRequest{id: "live1"})

    assert {:ok, task} =
             DefaultHandler.cancel_task(alice_server, %CancelTaskRequest{id: "live1"})

    assert task.status.state == :canceled

    assert_receive {:frames, _}, 2_000
  end

  defp wait_for_task(server, id, tries \\ 50) do
    case server.store.get(id, server.scope) do
      {:ok, _} ->
        :ok

      _ when tries > 0 ->
        Process.sleep(20)
        wait_for_task(server, id, tries - 1)

      _ ->
        flunk("task #{id} never appeared in store")
    end
  end
end
