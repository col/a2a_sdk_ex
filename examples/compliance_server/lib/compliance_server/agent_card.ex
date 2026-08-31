defmodule ComplianceServer.AgentCard do
  @moduledoc """
  The AgentCard this example advertises.

  Unlike the echo-server card, this one turns on every capability the SDK can
  actually serve — the TCK gates whole test classes on these flags (each push
  test skips unless `capabilities.pushNotifications` is true, and the streaming
  and subscribe tests skip unless `capabilities.streaming` is), so a modest card
  silently under-reports compliance.
  """
  alias A2A.Types.{AgentCapabilities, AgentCard, AgentInterface, AgentSkill}

  @spec card(String.t()) :: AgentCard.t()
  def card(base_url) do
    %AgentCard{
      name: "A2A Compliance Agent",
      description: "Implements the a2a-tck SUT scenario contract for compliance runs.",
      version: "0.1.0",
      default_input_modes: ["text/plain", "application/json"],
      default_output_modes: ["text/plain", "application/json"],
      capabilities: %AgentCapabilities{streaming: true, push_notifications: true},
      supported_interfaces: [
        %AgentInterface{url: base_url, protocol_binding: "JSONRPC", protocol_version: "1.0"},
        %AgentInterface{url: base_url, protocol_binding: "HTTP+JSON", protocol_version: "1.0"}
      ],
      skills: [
        %AgentSkill{
          id: "tck-scenarios",
          name: "TCK Scenarios",
          description: "Executes the behaviour named by the request's messageId prefix.",
          tags: ["compliance", "tck"]
        }
      ]
    }
  end
end
