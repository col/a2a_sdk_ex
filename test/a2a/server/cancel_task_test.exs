defmodule A2A.Server.CancelTaskTest do
  use ExUnit.Case, async: false

  alias A2A.Server.DefaultHandler
  alias A2A.Server.ResultAssembler
  alias A2A.Test.GatedExecutor
  alias A2A.Types.{CancelTaskRequest, Message, Part, SendMessageRequest}

  setup do
    name = :"srv_cancel_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_cancel_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{server: A2A.Server.handle(name)}
  end

  test "cancels a live task -> :canceled terminal", %{server: server} do
    # The GatedExecutor and the cancel below are keyed by task id, so the id is
    # pinned through the server's generator — spec 3.4.2 forbids a client-supplied
    # taskId for creating a task.
    server = %{server | executor: GatedExecutor, id_generator: fn -> "cid" end}
    caller = self()

    # Start a streaming send so the task runs concurrently (GatedExecutor blocks
    # after start_work until released) while we cancel it from this process.
    spawn_link(fn ->
      stream = DefaultHandler.send_message_stream(server, req("go"))
      send(caller, {:frames, Enum.to_list(stream)})
    end)

    wait_for_task(server, "cid")

    assert {:ok, task} = DefaultHandler.cancel_task(server, %CancelTaskRequest{id: "cid"})
    assert task.status.state == :canceled
    assert ResultAssembler.terminal?(task)

    assert {:ok, stored} = server.store.get("cid", server.scope)
    assert stored.status.state == :canceled
  end

  test "already-terminal task -> task_not_cancelable", %{server: server} do
    server = %{server | id_generator: fn -> "done1" end}
    {:ok, _} = DefaultHandler.send_message(server, req("hi"))

    assert {:error, %A2A.Error{code: :task_not_cancelable}} =
             DefaultHandler.cancel_task(server, %CancelTaskRequest{id: "done1"})
  end

  test "unknown task -> task_not_found", %{server: server} do
    assert {:error, %A2A.Error{code: :task_not_found}} =
             DefaultHandler.cancel_task(server, %CancelTaskRequest{id: "nope"})
  end

  test "cancel of a just-completed task -> not_cancelable, does not overwrite completed",
       %{server: server} do
    # Blocking send returns on the terminal broadcast, BEFORE the Execution process
    # handles its child :DOWN and self-stops — so the process may still be registered
    # and a cancel could take the live branch. The fresh-store-read terminal check
    # must reject it and NOT overwrite the completed task with :canceled. Whether the
    # process has already deregistered (cancel_not_live) or is still live is a race;
    # both branches must yield the same result. Loop a few immediate cancels to make
    # it likely we hit the still-live branch at least once.
    server = %{server | id_generator: fn -> "race1" end}

    {:ok, %{status: %{state: :completed}}} =
      DefaultHandler.send_message(server, req("hi"))

    for _ <- 1..5 do
      assert {:error, %A2A.Error{code: :task_not_cancelable}} =
               DefaultHandler.cancel_task(server, %CancelTaskRequest{id: "race1"})
    end

    assert {:ok, %{status: %{state: :completed}}} =
             DefaultHandler.get_task(server, %A2A.Types.GetTaskRequest{id: "race1"})
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
