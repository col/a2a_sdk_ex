defmodule EchoServer.AgentCard do
  @moduledoc "The AgentCard this example advertises."
  alias A2A.Types.{AgentCapabilities, AgentCard, AgentInterface, AgentSkill}

  @spec card(String.t()) :: AgentCard.t()
  def card(base_url) do
    %AgentCard{
      name: "Echo Agent",
      description: "Echoes whatever text it receives.",
      version: "0.1.0",
      default_input_modes: ["text/plain"],
      default_output_modes: ["text/plain"],
      capabilities: %AgentCapabilities{streaming: true},
      supported_interfaces: [
        %AgentInterface{url: base_url, protocol_binding: "JSONRPC", protocol_version: "1.0"},
        %AgentInterface{url: base_url, protocol_binding: "HTTP+JSON", protocol_version: "1.0"}
      ],
      skills: [
        %AgentSkill{
          id: "echo",
          name: "Echo",
          description: "Returns the input text prefixed with \"echo: \".",
          tags: ["demo"]
        }
      ]
    }
  end
end
