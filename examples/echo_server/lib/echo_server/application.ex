defmodule EchoServer.Application do
  @moduledoc false
  use Application

  @port 5001

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: EchoServer.PubSub},
      {A2A.Server.Supervisor,
       name: EchoServer.Agent.Server,
       executor: EchoServer.Agent,
       pubsub: EchoServer.PubSub,
       # A stream now closes only at a task-terminal state (ADR-0017), so a silent
       # task would hold its SSE connection for the SDK's 5-minute default — longer
       # than most proxies keep an idle connection open. 30s is a sane example
       # value; tune it below your own infrastructure's cutoff.
       stream_idle_timeout: 30_000,
       agent_card: EchoServer.Agent.agent_card()},
      {A2A.Standalone, server: EchoServer.Agent.Server, port: @port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: EchoServer.Supervisor)
  end
end
