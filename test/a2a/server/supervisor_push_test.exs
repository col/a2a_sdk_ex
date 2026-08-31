defmodule A2A.Server.SupervisorPushTest do
  use ExUnit.Case, async: false

  test "push disabled by default: handle carries push_notifications=false, no store" do
    name = :"srv_pushoff_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_pushoff_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    h = A2A.Server.handle(name)
    assert h.push_notifications == false
    assert h.push_store == nil
  end

  test "push enabled: handle carries defaults and the ETS store is running" do
    name = :"srv_pushon_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_pushon_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor,
       name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub, push_notifications: true}
    )

    h = A2A.Server.handle(name)
    assert h.push_notifications == true
    assert h.push_store == A2A.Server.PushConfigStore.ETS
    assert h.push_sender == A2A.Server.PushSender.Default
    assert h.push_timeout == 5_000
    assert is_function(h.push_url_validator, 1)
    assert Process.whereis(A2A.Server.PushConfigStore.ETS) |> is_pid()
  end
end
