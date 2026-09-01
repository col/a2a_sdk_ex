defmodule EchoServer.Agent do
  @moduledoc "The minimal readable example: echoes the caller's text back."
  use A2A.Server.Agent,
    name: "Echo Agent",
    description: "Echoes whatever text it receives.",
    version: "0.1.0",
    skills: [
      %{
        id: "echo",
        name: "Echo",
        description: "Returns the input text prefixed with \"echo: \".",
        tags: ["demo"]
      }
    ]

  alias A2A.Server.RequestContext

  @impl A2A.Server.Agent
  def handle_message(ctx) do
    reply() |> artifact("echo", "echo: " <> RequestContext.user_input(ctx))
  end
end
