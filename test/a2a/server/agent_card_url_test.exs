defmodule A2A.Server.AgentCardURLTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias A2A.Server.AgentCardURL
  alias A2A.Types.{AgentCard, AgentInterface}

  defp card(ifaces), do: %AgentCard{name: "c", supported_interfaces: ifaces}

  test "fills nil interface urls from a standalone (root) request" do
    conn = conn(:get, "/.well-known/agent-card.json")
    resolved = AgentCardURL.resolve(card([%AgentInterface{protocol_binding: "JSONRPC"}]), conn)
    assert [%AgentInterface{url: "http://www.example.com/"}] = resolved.supported_interfaces
  end

  test "honors a mount path via script_name" do
    conn = %{conn(:get, "/.well-known/agent-card.json") | script_name: ["agents", "echo"]}
    resolved = AgentCardURL.resolve(card([%AgentInterface{protocol_binding: "JSONRPC"}]), conn)

    assert [%AgentInterface{url: "http://www.example.com/agents/echo/"}] =
             resolved.supported_interfaces
  end

  test "omits default ports and leaves pinned urls verbatim" do
    conn = %{conn(:get, "/") | scheme: :https, host: "api.test", port: 443}

    resolved =
      AgentCardURL.resolve(
        card([
          %AgentInterface{protocol_binding: "JSONRPC"},
          %AgentInterface{protocol_binding: "HTTP+JSON", url: "https://pinned.example/a2a"}
        ]),
        conn
      )

    assert [
             %AgentInterface{url: "https://api.test/"},
             %AgentInterface{url: "https://pinned.example/a2a"}
           ] = resolved.supported_interfaces
  end

  test "empty supported_interfaces stays empty" do
    assert %AgentCard{supported_interfaces: []} = AgentCardURL.resolve(card([]), conn(:get, "/"))
  end
end
