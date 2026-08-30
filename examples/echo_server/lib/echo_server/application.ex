defmodule EchoServer.Application do
  @moduledoc false
  use Application

  @port 5001

  @impl true
  def start(_type, _args) do
    base_url = "http://localhost:#{@port}/"

    children = [
      {Phoenix.PubSub, name: EchoServer.PubSub},
      {A2A.Server.Supervisor,
       name: EchoServer.Agent,
       executor: EchoServer.Executor,
       pubsub: EchoServer.PubSub,
       agent_card: EchoServer.AgentCard.card(base_url)},
      {A2A.Standalone, server: EchoServer.Agent, port: @port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: EchoServer.Supervisor)
  end
end
