defmodule A2A.Client.CardResolverTest do
  use ExUnit.Case, async: true
  alias A2A.Client.{CardResolver, Config, HTTP.Stub}
  alias A2A.Types.{AgentCapabilities, AgentCard, AgentInterface}

  defp cfg, do: Config.new(http_client: Stub)

  test "resolve fetches and decodes the well-known card" do
    card = %AgentCard{
      name: "Bot",
      version: "1.0",
      capabilities: %AgentCapabilities{streaming: true},
      supported_interfaces: [
        %AgentInterface{protocol_binding: "JSONRPC", url: "http://x/", protocol_version: "1.0"}
      ]
    }

    Stub.put(%{
      {:get, "/.well-known/agent-card.json"} => %{
        status: 200,
        headers: [],
        body: A2A.JSON.encode!(card)
      }
    })

    assert {:ok, %AgentCard{name: "Bot"}} = CardResolver.resolve("http://x", cfg(), [])
  end

  test "resolve surfaces a non-2xx as A2A.Error" do
    Stub.put(%{
      {:get, "/.well-known/agent-card.json"} => %{
        status: 404,
        headers: [],
        body: ~s({"error":{"code":404,"status":"NOT_FOUND","message":"no card"}})
      }
    })

    assert {:error, %A2A.Error{}} = CardResolver.resolve("http://x", cfg(), [])
  end

  test "fetch_agent_card/2 is the public entry" do
    card = %AgentCard{name: "Bot", version: "1.0"}

    Stub.put(%{
      {:get, "/.well-known/agent-card.json"} => %{
        status: 200,
        headers: [],
        body: A2A.JSON.encode!(card)
      }
    })

    assert {:ok, %AgentCard{name: "Bot"}} =
             A2A.Client.fetch_agent_card("http://x", http_client: Stub)
  end
end
