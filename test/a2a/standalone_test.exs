defmodule A2A.StandaloneTest do
  use ExUnit.Case, async: false

  alias A2A.Types.{AgentCard, Message, Part, SendMessageRequest}

  @card %AgentCard{name: "Echo", version: "0.1.0"}

  setup do
    name = :"srv_std_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_std_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor,
       name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub, agent_card: @card}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)

    # Port 0 => OS assigns a free port; discover it from the running Bandit
    # supervisor. On the pinned bandit/thousand_island versions, the pid
    # returned by A2A.Standalone.start_link/1 is itself the
    # ThousandIsland.Server, so listener_info/1 is called directly on it
    # (drilling into its :listener child and calling listener_info/1 on that
    # raw ThousandIsland.Listener pid raises a FunctionClauseError).
    pid = start_supervised!({A2A.Standalone, server: name, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    %{port: port}
  end

  test "serves the agent card over real HTTP", %{port: port} do
    {:ok, {{_, 200, _}, _headers, body}} =
      :httpc.request(:get, {~c"http://localhost:#{port}/.well-known/agent-card.json", []}, [], [])

    assert {:ok, %AgentCard{name: "Echo"}} = A2A.JSON.decode(to_string(body), AgentCard)
  end

  test "handles message/send over real HTTP", %{port: port} do
    payload =
      %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "message/send",
        "params" =>
          A2A.JSON.to_json_map(%SendMessageRequest{
            message: %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
          })
      }
      |> Jason.encode!()

    {:ok, {{_, 200, _}, _headers, body}} =
      :httpc.request(
        :post,
        {~c"http://localhost:#{port}/", [], ~c"application/json", payload},
        [],
        []
      )

    assert %{"result" => %{"task" => %{"status" => %{"state" => "TASK_STATE_COMPLETED"}}}} =
             Jason.decode!(to_string(body))
  end

  describe "child_spec/1 Bandit option passthrough" do
    # The Bandit options are the single argument in the built child spec's
    # `start` MFA — inspect them without booting a socket.
    defp bandit_opts(a2a_opts) do
      %{start: {Bandit, :start_link, [opts]}} = A2A.Standalone.child_spec(a2a_opts)
      opts
    end

    test "forwards :bandit options to Bandit and always sets our plug" do
      opts = bandit_opts(server: MyAgent, bandit: [scheme: :https, ip: {127, 0, 0, 1}])

      assert opts[:scheme] == :https
      assert opts[:ip] == {127, 0, 0, 1}
      assert opts[:plug] == {A2A.Plug.Router, [server: MyAgent]}
    end

    test "top-level :port seeds the port; defaults to 4000" do
      assert bandit_opts(server: MyAgent)[:port] == 4000
      assert bandit_opts(server: MyAgent, port: 4001)[:port] == 4001
    end

    test "a :port inside :bandit overrides the top-level :port convenience" do
      opts = bandit_opts(server: MyAgent, port: 4001, bandit: [port: 4443])
      assert opts[:port] == 4443
    end

    test "the caller cannot override the A2A plug via :bandit" do
      opts = bandit_opts(server: MyAgent, bandit: [plug: SomeOther.Plug])
      assert opts[:plug] == {A2A.Plug.Router, [server: MyAgent]}
    end
  end
end
