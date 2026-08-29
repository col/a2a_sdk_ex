defmodule A2A.Server.SupervisorTest do
  use ExUnit.Case, async: false

  test "starts the tree and exposes a resolved handle" do
    name = :"srv_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    handle = A2A.Server.handle(name)
    assert %A2A.Server{executor: A2A.Test.EchoExecutor, pubsub: ^pubsub} = handle
    assert Process.whereis(handle.registry) |> is_pid()
    assert Process.whereis(handle.dyn_sup) |> is_pid()
    assert is_function(handle.id_generator, 0)
  end
end
