defmodule A2A.Plug.ExtendedCardBindingTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.REST
  alias A2A.Plug.Router
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Types.{AgentCapabilities, AgentCard}

  @advertised %AgentCard{
    name: "Base",
    version: "1",
    default_input_modes: ["text/plain"],
    capabilities: %AgentCapabilities{extended_agent_card: true}
  }
  @extended %AgentCard{name: "Extended", version: "1", default_input_modes: ["text/plain"]}

  setup do
    name = :"srv_extcard_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_extcard_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor,
       name: name,
       executor: A2A.Test.EchoExecutor,
       pubsub: pubsub,
       agent_card: @advertised,
       extended_agent_card_resolver: fn _user -> @extended end}
    )

    %{opts: Router.init(server: name), name: name}
  end

  test "REST GET /extendedAgentCard returns the extended card", %{opts: opts} do
    conn = Router.call(conn(:get, "/extendedAgentCard"), opts)
    assert conn.status == 200
    assert {:ok, %AgentCard{name: "Extended"}} = A2A.JSON.decode(conn.resp_body, AgentCard)
  end

  test "JSON-RPC GetExtendedAgentCard returns the extended card", %{opts: opts} do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "GetExtendedAgentCard",
        "params" => %{}
      })

    resp =
      conn(:post, "/", body)
      |> put_req_header("content-type", "application/json")
      |> Router.call(opts)
      |> then(& &1.resp_body)
      |> Jason.decode!()

    assert get_in(resp, ["result", "name"]) == "Extended"
  end

  # CONTROLLER RULING: the brief's version of this test started a second
  # `A2A.Server.Supervisor` tree, which collides on the globally-named ETS
  # `TaskStore` (`name: __MODULE__`) — see CLAUDE.md's known-gotchas section.
  # Instead, reuse the setup tree's handle and override the field directly,
  # calling `A2A.Plug.REST` rather than routing through a second tree.
  test "not configured ⇒ FAILED_PRECONDITION / 400", %{name: name} do
    server = %{A2A.Server.handle(name) | extended_agent_card_resolver: nil}
    assert {:error, 400, body} = REST.get_extended_agent_card(server)
    assert body["error"]["status"] == "FAILED_PRECONDITION"
  end
end
