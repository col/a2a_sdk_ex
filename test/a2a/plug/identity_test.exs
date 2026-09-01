defmodule A2A.Plug.IdentityTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.Identity
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Types.AgentCard
  alias A2A.User

  @card %AgentCard{name: "Echo", version: "0.1.0", default_input_modes: ["text/plain"]}

  setup do
    name = :"srv_identity_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_identity_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor,
       name: name,
       executor: A2A.Test.EchoExecutor,
       pubsub: pubsub,
       agent_card: @card,
       user_resolver: fn conn ->
         case Plug.Conn.get_req_header(conn, "x-user") do
           [id | _] -> %User{id: id, authenticated?: true}
           [] -> User.anonymous()
         end
       end}
    )

    %{name: name}
  end

  test "resolves the user from the request and stashes it on conn.private", %{name: name} do
    conn =
      conn(:post, "/", "")
      |> put_req_header("x-user", "alice")
      |> Identity.call(server: name)

    assert %User{id: "alice", authenticated?: true} = Identity.current_user(conn)
  end

  test "default (no matching header) is an anonymous user", %{name: name} do
    conn = conn(:post, "/", "") |> Identity.call(server: name)
    assert Identity.current_user(conn) == User.anonymous()
  end

  test "current_user/1 defaults to anonymous when the plug never ran" do
    assert Identity.current_user(conn(:get, "/")) == User.anonymous()
  end

  test "the well-known card path is exempt (no resolution)", %{name: name} do
    conn = conn(:get, "/.well-known/agent-card.json") |> Identity.call(server: name)
    refute Map.has_key?(conn.private, :a2a_user)
  end
end
