defmodule A2A.Client.Transport.SelectorTest do
  use ExUnit.Case, async: true
  alias A2A.Client.Transport.Selector
  alias A2A.Types.{AgentCard, AgentInterface}

  defp card(interfaces), do: %AgentCard{supported_interfaces: interfaces}

  defp iface(b, url, v \\ "1.0"),
    do: %AgentInterface{protocol_binding: b, url: url, protocol_version: v}

  test "server preference: first advertised+implemented wins" do
    c = card([iface("JSONRPC", "http://x/rpc"), iface("HTTP+JSON", "http://x")])
    assert {:ok, {A2A.Client.Transport.JSONRPC, "http://x/rpc"}} = Selector.select(c, [])
  end

  test "client preference overrides card order" do
    c = card([iface("JSONRPC", "http://x/rpc"), iface("HTTP+JSON", "http://x")])
    assert {:ok, {A2A.Client.Transport.REST, "http://x"}} = Selector.select(c, ["HTTP+JSON"])
  end

  test "prefers protocol_version 1.0 when a binding repeats" do
    c = card([iface("JSONRPC", "http://old", "0.3"), iface("JSONRPC", "http://new", "1.0")])
    assert {:ok, {A2A.Client.Transport.JSONRPC, "http://new"}} = Selector.select(c, [])
  end

  test "case-insensitive binding match" do
    c = card([iface("jsonrpc", "http://x/rpc")])
    assert {:ok, {A2A.Client.Transport.JSONRPC, "http://x/rpc"}} = Selector.select(c, [])
  end

  test "no overlap → unsupported_operation" do
    c = card([iface("GRPC", "http://x")])
    assert {:error, %A2A.Error{code: :unsupported_operation}} = Selector.select(c, [])
  end
end
