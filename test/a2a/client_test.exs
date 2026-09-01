defmodule A2A.ClientTest do
  use ExUnit.Case, async: true
  alias A2A.Client
  alias A2A.Client.HTTP.Stub
  alias A2A.Types.{AgentCapabilities, AgentCard, AgentInterface, Message, Part, Task}

  defp card do
    %AgentCard{
      name: "Bot",
      version: "1.0",
      capabilities: %AgentCapabilities{streaming: true},
      supported_interfaces: [
        %AgentInterface{protocol_binding: "JSONRPC", url: "http://x/", protocol_version: "1.0"}
      ]
    }
  end

  test "connect(%AgentCard{}) selects transport, no fetch" do
    {:ok, c} = Client.connect(card(), http_client: Stub)
    assert c.transport == A2A.Client.Transport.JSONRPC
    assert c.endpoint == "http://x/"
    assert Client.agent_card(c).name == "Bot"
  end

  test "connect(url) fetches then selects" do
    Stub.put(%{
      {:get, "/.well-known/agent-card.json"} => %{
        status: 200,
        headers: [],
        body: A2A.JSON.encode!(card())
      }
    })

    {:ok, c} = Client.connect("http://x", http_client: Stub)
    assert c.transport == A2A.Client.Transport.JSONRPC
  end

  test "get_task delegates through the transport" do
    {:ok, c} = Client.connect(card(), http_client: Stub)

    Stub.put(%{
      {:post, "/"} => %{
        status: 200,
        headers: [],
        body:
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "id" => 1,
            "result" => %{
              "id" => "t1",
              "contextId" => "c1",
              "status" => %{"state" => "TASK_STATE_COMPLETED"}
            }
          })
      }
    })

    assert {:ok, %Task{id: "t1"}} = Client.get_task(c, "t1")
  end

  test "send_message wraps a bare Message into a request" do
    {:ok, c} = Client.connect(card(), http_client: Stub)
    out = %Message{message_id: "m2", role: :agent, parts: [Part.text("yo")]}

    Stub.put(%{
      {:post, "/"} => %{
        status: 200,
        headers: [],
        body:
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "id" => 1,
            "result" => %{"message" => A2A.JSON.to_json_map(out)}
          })
      }
    })

    assert {:ok, %Message{message_id: "m2"}} =
             Client.send_message(c, %Message{
               message_id: "m1",
               role: :user,
               parts: [Part.text("hi")]
             })
  end
end
