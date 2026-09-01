defmodule A2A.Server.RequestUserTest do
  use ExUnit.Case, async: false

  alias A2A.Server
  alias A2A.Server.DefaultHandler
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Server.TaskStore.ETS, as: TaskStoreETS
  alias A2A.Test.CaptureUserExecutor
  alias A2A.Types.{Message, Part, SendMessageRequest}
  alias A2A.User

  setup do
    name = :"srv_requser_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_requser_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor, name: name, executor: A2A.Test.CaptureUserExecutor, pubsub: pubsub}
    )

    :ets.delete_all_objects(TaskStoreETS)
    %{server: Server.handle(name)}
  end

  defp send_as(server, user, text) do
    req = %SendMessageRequest{
      message: %Message{role: :user, parts: [Part.text(text)]}
    }

    DefaultHandler.send_message(Server.for_request(server, user), req)
  end

  test "the executor observes the resolved caller", %{server: server} do
    user = %User{id: "alice", authenticated?: true}
    {:ok, task} = send_as(server, user, "hi")
    assert CaptureUserExecutor.captured(task.id) == user
  end

  test "an unconfigured caller is anonymous", %{server: server} do
    {:ok, task} = send_as(server, User.anonymous(), "hi")
    assert CaptureUserExecutor.captured(task.id) == User.anonymous()
  end
end
