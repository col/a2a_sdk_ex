defmodule A2A.Plug.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.{Cache, Router}
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Server.TaskStore.ETS, as: TaskStoreETS
  alias A2A.Types.{AgentCard, Message, Part, SendMessageRequest}

  @card %AgentCard{name: "Echo", version: "0.1.0", default_input_modes: ["text/plain"]}

  setup do
    name = :"srv_router_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_router_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor,
       name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub, agent_card: @card}
    )

    :ets.delete_all_objects(TaskStoreETS)
    %{opts: Router.init(server: name), name: name}
  end

  defp post(opts, map) do
    conn(:post, "/", Jason.encode!(map))
    |> put_req_header("content-type", "application/json")
    |> Router.call(opts)
  end

  test "GET agent card returns the configured card", %{opts: opts} do
    conn = Router.call(conn(:get, "/.well-known/agent-card.json"), opts)
    assert conn.status == 200
    assert {:ok, %AgentCard{name: "Echo"}} = A2A.JSON.decode(conn.resp_body, AgentCard)
  end

  describe "agent card caching (spec §8.6)" do
    test "the card carries validators a client can revalidate against", %{opts: opts} do
      conn = Router.call(conn(:get, "/.well-known/agent-card.json"), opts)

      assert conn.status == 200
      assert [etag] = get_resp_header(conn, "etag")
      # A strong validator, quoted per RFC 9110.
      assert etag =~ ~r/^"[a-f0-9]+"$/
      assert [_last_modified] = get_resp_header(conn, "last-modified")
      assert [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control =~ "max-age"
    end

    test "the etag is stable across requests", %{opts: opts} do
      fetch = fn -> Router.call(conn(:get, "/.well-known/agent-card.json"), opts) end

      assert [etag] = get_resp_header(fetch.(), "etag")
      assert [^etag] = get_resp_header(fetch.(), "etag")
    end

    test "the etag is the served body's validator", %{opts: opts} do
      conn = Router.call(conn(:get, "/.well-known/agent-card.json"), opts)

      assert [etag] = get_resp_header(conn, "etag")
      assert etag == Cache.etag(conn.resp_body)
      refute etag == Cache.etag(conn.resp_body <> " ")
    end

    test "a matching If-None-Match gets 304 with no body", %{opts: opts} do
      conn = Router.call(conn(:get, "/.well-known/agent-card.json"), opts)
      assert [etag] = get_resp_header(conn, "etag")

      revalidated =
        conn(:get, "/.well-known/agent-card.json")
        |> put_req_header("if-none-match", etag)
        |> Router.call(opts)

      assert revalidated.status == 304
      assert revalidated.resp_body == ""
      # RFC 9110 §15.4.5: a 304 carries the validators the client would cache.
      assert [^etag] = get_resp_header(revalidated, "etag")
    end

    test "a stale If-None-Match gets the card", %{opts: opts} do
      conn =
        conn(:get, "/.well-known/agent-card.json")
        |> put_req_header("if-none-match", ~s("stale"))
        |> Router.call(opts)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["name"]
    end

    test "If-None-Match: * always matches an existing card", %{opts: opts} do
      conn =
        conn(:get, "/.well-known/agent-card.json")
        |> put_req_header("if-none-match", "*")
        |> Router.call(opts)

      assert conn.status == 304
    end
  end

  test "GET agent card 404s when no card configured" do
    # Stop the setup-started tree first: the default TaskStore.ETS child is a
    # globally-named GenServer/table, so two live trees collide.
    stop_supervised!(ServerSupervisor)

    name = :"srv_nocard_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_nocard_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    opts = Router.init(server: name)
    conn = Router.call(conn(:get, "/.well-known/agent-card.json"), opts)
    assert conn.status == 404
  end

  test "POST SendMessage echoes into a completed task", %{opts: opts} do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "SendMessage",
      "params" =>
        A2A.JSON.to_json_map(%SendMessageRequest{
          message: %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
        })
    }

    conn = post(opts, body)
    assert conn.status == 200

    assert %{"result" => %{"task" => %{"status" => %{"state" => "TASK_STATE_COMPLETED"}}}} =
             Jason.decode!(conn.resp_body)
  end

  test "POST unknown method -> -32601 with 200 envelope", %{opts: opts} do
    conn = post(opts, %{"jsonrpc" => "2.0", "id" => 2, "method" => "tasks/bogus", "params" => %{}})
    assert conn.status == 200
    assert %{"error" => %{"code" => -32_601}} = Jason.decode!(conn.resp_body)
  end

  test "POST oversized body -> -32600 with 200 envelope", %{opts: opts} do
    # Plug's default read_body length limit is 8_000_000 bytes; exceed it so
    # read_body/1 returns {:more, partial, conn} instead of {:ok, body, conn}.
    oversized = String.duplicate("x", 8_000_050)

    conn =
      conn(:post, "/", oversized)
      |> put_req_header("content-type", "application/json")
      |> Router.call(opts)

    assert conn.status == 200
    assert %{"error" => %{"code" => -32_600}} = Jason.decode!(conn.resp_body)
  end

  test "POST malformed JSON -> -32700", %{opts: opts} do
    conn =
      conn(:post, "/", "{bad")
      |> put_req_header("content-type", "application/json")
      |> Router.call(opts)

    assert conn.status == 200
    assert %{"error" => %{"code" => -32_700}} = Jason.decode!(conn.resp_body)
  end
end
