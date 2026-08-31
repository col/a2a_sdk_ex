defmodule A2A.Server.SendMessageValidationTest do
  @moduledoc """
  `SendMessageRequest.message` is required. A request that omits it decodes to
  `message: nil` (proto3-JSON has no required-field concept), so the handler —
  the chokepoint both HTTP bindings land on — must reject it as `:invalid_params`
  rather than raising.
  """
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias A2A.Plug.JSONRPC
  alias A2A.Plug.Router
  alias A2A.Server.DefaultHandler
  alias A2A.Types.SendMessageRequest

  setup do
    name = :"srv_smv_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_smv_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{server: A2A.Server.handle(name), name: name}
  end

  test "send_message without a message returns invalid_params", %{server: server} do
    assert {:error, %A2A.Error{code: :invalid_params}} =
             DefaultHandler.send_message(server, %SendMessageRequest{message: nil})
  end

  test "send_message_stream without a message returns invalid_params", %{server: server} do
    assert {:error, %A2A.Error{code: :invalid_params}} =
             DefaultHandler.send_message_stream(server, %SendMessageRequest{message: nil})
  end

  test "SendMessage over JSON-RPC without a message renders -32602", %{server: server} do
    assert {:error, %{"error" => %{"code" => -32_602}}} =
             JSONRPC.dispatch(server, %{method: "SendMessage", params: %{}, id: 1})
  end

  test "SendStreamingMessage over JSON-RPC without a message renders -32602", %{server: server} do
    assert {:error, %{"error" => %{"code" => -32_602}}} =
             JSONRPC.dispatch(server, %{method: "SendStreamingMessage", params: %{}, id: 1})
  end

  test "POST /message:send without a message renders 400 INVALID_ARGUMENT", %{name: name} do
    conn =
      :post
      |> conn("/message:send", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(Router.init(server: name))

    assert conn.status == 400

    assert %{"code" => 3, "details" => [%{"reason" => "INVALID_ARGUMENT"}]} =
             Jason.decode!(conn.resp_body)
  end
end
