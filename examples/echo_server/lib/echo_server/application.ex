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
       agent_card: EchoServer.Agent.agent_card()},
      {A2A.Standalone, server: EchoServer.Agent.Server, port: @port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: EchoServer.Supervisor)
  end
end
