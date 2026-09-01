defmodule A2A.Plug.ServiceParamsTest do
  @moduledoc """
  A2A service parameters (spec §3.2.6) are transmitted as HTTP headers and
  validated before dispatch, so both bindings reject the same requests — each in
  its own error shape.
  """
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias A2A.Plug.Router
  alias A2A.Server.Supervisor, as: ServerSupervisor
  alias A2A.Server.TaskStore.ETS, as: TaskStoreETS
  alias A2A.Types.{AgentCard, Message, Part}

  @card %AgentCard{name: "Echo", version: "0.1.0", default_input_modes: ["text/plain"]}

  setup do
    name = :"srv_sp_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_sp_#{System.unique_integer([:positive])}"

    start_supervised!(
      {ServerSupervisor,
       name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub, agent_card: @card}
    )

    :ets.delete_all_objects(TaskStoreETS)
    %{opts: Router.init(server: name)}
  end

  defp message do
    A2A.JSON.to_json_map(%Message{
      message_id: "m_#{System.unique_integer([:positive])}",
      role: :user,
      parts: [Part.text("hi")]
    })
  end

  # POST the JSON-RPC envelope, with whatever headers the case is about.
  defp jsonrpc(opts, headers) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "SendMessage",
        "params" => %{"message" => message()}
      })

    :post
    |> conn("/", body)
    |> with_headers(headers)
    |> Router.call(opts)
  end

  defp rest(opts, headers) do
    :post
    |> conn("/message:send", Jason.encode!(%{"message" => message()}))
    |> with_headers(headers)
    |> Router.call(opts)
  end

  defp with_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  defp reason(conn) do
    assert %{"error" => %{"details" => [detail]}} = json(conn)
    detail["reason"]
  end

  @json [{"content-type", "application/json"}]

  describe "A2A-Version (spec §6.4)" do
    test "JSON-RPC rejects an unsupported version with -32009", %{opts: opts} do
      conn = jsonrpc(opts, @json ++ [{"a2a-version", "99.0"}])

      assert conn.status == 200
      assert %{"error" => %{"code" => -32_009, "data" => [detail]}} = json(conn)
      assert detail["reason"] == "VERSION_NOT_SUPPORTED"
    end

    test "REST rejects an unsupported version with 400", %{opts: opts} do
      conn = rest(opts, @json ++ [{"a2a-version", "99.0"}])

      assert conn.status == 400
      assert reason(conn) == "VERSION_NOT_SUPPORTED"
    end

    test "the version we implement is accepted", %{opts: opts} do
      assert %{"result" => _} = jsonrpc(opts, @json ++ [{"a2a-version", "1.0"}]) |> json()
    end

    test "a patch-level version matches on Major.Minor", %{opts: opts} do
      # Spec §6.3: "Agents MUST process requests using the semantics of the
      # requested A2A-Version (matching Major.Minor)".
      assert %{"result" => _} = jsonrpc(opts, @json ++ [{"a2a-version", "1.0.7"}]) |> json()
    end

    test "an absent version header is accepted", %{opts: opts} do
      assert %{"result" => _} = jsonrpc(opts, @json) |> json()
    end

    test "an empty version header is accepted", %{opts: opts} do
      # VER-SERVER-003: an empty header must not be treated as a rejectable
      # version — the client simply did not state one.
      assert %{"result" => _} = jsonrpc(opts, @json ++ [{"a2a-version", ""}]) |> json()
    end

    test "the version may also arrive as a query parameter", %{opts: opts} do
      # Spec §6.3: "Clients MAY provide the A2A-Version as a request parameter
      # instead of a header" — so the query form must be rejected the same way.
      conn = :get |> conn("/tasks?A2A-Version=99.0") |> Router.call(opts)

      assert conn.status == 400
      assert reason(conn) == "VERSION_NOT_SUPPORTED"
    end

    test "agent card discovery is not version-gated", %{opts: opts} do
      conn =
        :get
        |> conn("/.well-known/agent-card.json")
        |> put_req_header("a2a-version", "99.0")
        |> Router.call(opts)

      assert conn.status == 200
    end
  end

  describe "Content-Type (spec §11.1)" do
    test "JSON-RPC rejects a non-JSON content type with -32005", %{opts: opts} do
      conn = jsonrpc(opts, [{"content-type", "text/plain"}])

      assert %{"error" => %{"code" => -32_005, "data" => [detail]}} = json(conn)
      assert detail["reason"] == "CONTENT_TYPE_NOT_SUPPORTED"
    end

    test "REST rejects a non-JSON content type with 415", %{opts: opts} do
      conn = rest(opts, [{"content-type", "text/plain"}])

      assert conn.status == 415
      assert reason(conn) == "CONTENT_TYPE_NOT_SUPPORTED"
    end

    test "the A2A media type is accepted alongside application/json", %{opts: opts} do
      # `application/a2a+json` is registered for this binding (§14.1.1); we do not
      # emit it, but refusing to accept it would reject a conformant client.
      conn = rest(opts, [{"content-type", "application/a2a+json"}])
      assert conn.status == 200
    end

    test "a charset parameter does not change the media type", %{opts: opts} do
      conn = rest(opts, [{"content-type", "application/json; charset=utf-8"}])
      assert conn.status == 200
    end

    test "a bodyless GET is not content-type gated", %{opts: opts} do
      conn = :get |> conn("/tasks") |> Router.call(opts)
      assert conn.status == 200
    end
  end
end
