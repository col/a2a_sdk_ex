defmodule ComplianceServer.Application do
  @moduledoc false
  use Application

  @default_port 5002

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:compliance_server, :port, @default_port)
    base_url = "http://localhost:#{port}/"

    children =
      [
        {Phoenix.PubSub, name: ComplianceServer.PubSub},
        {A2A.Server.Supervisor,
         name: ComplianceServer.Agent,
         executor: ComplianceServer.Executor,
         pubsub: ComplianceServer.PubSub,
         push_notifications: true,
         # A stream now closes only at a task-terminal state (ADR-0017), so a
         # scenario that parks at `input_required` and is never answered holds the
         # SSE connection until this fires. The SDK default is 5 minutes; a TCK run
         # should fail fast rather than hang, and nothing here is legitimately
         # silent for 30s.
         stream_idle_timeout: 30_000,
         agent_card: ComplianceServer.AgentCard.card(base_url)}
      ] ++ http_children(port)

    Supervisor.start_link(children, strategy: :one_for_one, name: ComplianceServer.Supervisor)
  end

  # The unit suite exercises pure modules; binding a fixed port there would fail
  # whenever a compliance run already holds it (see config/test.exs).
  defp http_children(port) do
    case Application.get_env(:compliance_server, :start_http?, true) do
      true -> [{A2A.Standalone, server: ComplianceServer.Agent, port: port}]
      false -> []
    end
  end
end
