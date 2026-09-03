defmodule ClientServer.Application do
  @moduledoc false
  use Application

  @default_port 4010

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:client_server, :port, @default_port)
    listen? = Application.get_env(:client_server, :listen, true)

    children =
      [
        {Phoenix.PubSub, name: ClientServer.PubSub},
        {
          A2A.Server.Supervisor,
          # See EchoServer.Application: a stream closes only at task-terminal
          # (ADR-0017), so bound a silent task's SSE connection below most
          # proxies' idle cutoff.
          name: ClientServer.Agent,
          executor: ClientServer.Agent,
          pubsub: ClientServer.PubSub,
          user_resolver: &ClientServer.user_from_conn/1,
          extended_agent_card_resolver: &ClientServer.extended_card/1,
          stream_idle_timeout: 30_000,
          agent_card: ClientServer.Agent.agent_card()
        }
      ] ++ http_children(listen?, port)

    Supervisor.start_link(children, strategy: :one_for_one, name: ClientServer.Supervisor)
  end

  # The example's own `mix test` (if any is ever added) shouldn't bind a port;
  # `config/test.exs` turns this off, mirroring compliance_server.
  defp http_children(false, _port), do: []
  defp http_children(true, port), do: [{A2A.Standalone, server: ClientServer.Agent, port: port}]
end
