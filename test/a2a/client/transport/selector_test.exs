defmodule A2A.Client.Transport.SelectorTest do
  use ExUnit.Case, async: true
  alias A2A.Client.Transport.Selector
  alias A2A.Types.{AgentCard, AgentInterface}

  defp card(interfaces), do: %AgentCard{supported_interfaces: interfaces}

  defp iface(binding, url, version \\ "1.0"),
    do: %AgentInterface{protocol_binding: binding, url: url, protocol_version: version}

  test "server preference: first advertised+implemented wins" do
    agent_card = card([iface("JSONRPC", "http://x/rpc"), iface("HTTP+JSON", "http://x")])
    assert {:ok, {A2A.Client.Transport.JSONRPC, "http://x/rpc"}} = Selector.select(agent_card, [])
  end

  test "client preference overrides card order" do
    agent_card = card([iface("JSONRPC", "http://x/rpc"), iface("HTTP+JSON", "http://x")])

    assert {:ok, {A2A.Client.Transport.REST, "http://x"}} =
             Selector.select(agent_card, ["HTTP+JSON"])
  end

  test "prefers protocol_version 1.0 when a binding repeats" do
    agent_card =
      card([iface("JSONRPC", "http://old", "0.3"), iface("JSONRPC", "http://new", "1.0")])

    assert {:ok, {A2A.Client.Transport.JSONRPC, "http://new"}} = Selector.select(agent_card, [])
  end

  test "case-insensitive binding match" do
    agent_card = card([iface("jsonrpc", "http://x/rpc")])
    assert {:ok, {A2A.Client.Transport.JSONRPC, "http://x/rpc"}} = Selector.select(agent_card, [])
  end

  test "no overlap → unsupported_operation" do
    agent_card = card([iface("GRPC", "http://x")])
    assert {:error, %A2A.Error{code: :unsupported_operation}} = Selector.select(agent_card, [])
  end

  test "nil supported_interfaces → unsupported_operation, not a crash" do
    agent_card = card(nil)
    assert {:error, %A2A.Error{code: :unsupported_operation}} = Selector.select(agent_card, [])
  end
end
