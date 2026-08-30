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

  test "handle carries a configurable drain_timeout, defaulting to :infinity" do
    name = :"srv_dt_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_dt_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    assert %A2A.Server{drain_timeout: :infinity} = A2A.Server.handle(name)

    # Stop the first tree before starting the second: the default TaskStore.ETS
    # child is a globally-named GenServer/table, so two live trees collide.
    stop_supervised!(A2A.Server.Supervisor)

    name2 = :"srv_dt2_#{System.unique_integer([:positive])}"
    pubsub2 = :"pubsub_dt2_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor,
       name: name2, executor: A2A.Test.EchoExecutor, pubsub: pubsub2, drain_timeout: 5_000},
      id: :srv_dt2
    )

    assert %A2A.Server{drain_timeout: 5_000} = A2A.Server.handle(name2)
  end
end
