defmodule ClientServer.Agent do
  @moduledoc """
  The client SDK's integration-test target: echoes text back, same as
  `EchoServer.Agent`, but advertises a dual-interface card (`JSONRPC` +
  `HTTP+JSON` at the same served URL) and turns on `extended_agent_card` so the
  client's `GetExtendedAgentCard` path has something to exercise.
  """
  use A2A.Server.Agent,
    name: "Client Test Agent",
    description: "Echoes whatever text it receives; used as the client SDK's integration SUT.",
    version: "0.1.0",
    capabilities: %A2A.Types.AgentCapabilities{streaming: true, extended_agent_card: true},
    skills: [
      %{
        id: "echo",
        name: "Echo",
        description: "Returns the input text prefixed with \"echo: \".",
        tags: ["demo"]
      }
    ]

  alias A2A.Server.RequestContext
  alias A2A.Types.AgentInterface

  @impl A2A.Server.Agent
  def handle_message(ctx) do
    reply() |> artifact("echo", "echo: " <> RequestContext.user_input(ctx))
  end

  # The macro's `use` opts can't know the serving port, so the interfaces'
  # `url` is filled in here from runtime config (mirrors
  # `ComplianceServer.AgentCard.card/1`, just wired through the overridable
  # `agent_card/1` callback instead of a free function).
  @impl A2A.Server.Agent
  def agent_card(card) do
    url = base_url()

    %{
      card
      | supported_interfaces: [
          %AgentInterface{url: url, protocol_binding: "JSONRPC", protocol_version: "1.0"},
          %AgentInterface{url: url, protocol_binding: "HTTP+JSON", protocol_version: "1.0"}
        ]
    }
  end

  defp base_url do
    port = Application.get_env(:client_server, :port, 4010)
    "http://localhost:#{port}/"
  end
end
