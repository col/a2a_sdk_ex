defmodule ClientServer do
  @moduledoc """
  Top-level helpers wired into `A2A.Server.Supervisor` by
  `ClientServer.Application`: identity resolution (`user_from_conn/1`) and the
  authenticated extended card (`extended_card/1`).
  """
  alias A2A.Types.{AgentCapabilities, AgentCard, AgentSkill}
  alias A2A.User

  @doc """
  Resolves the caller from the `Authorization: Bearer <token>` header. The
  fixed token `"secret"` authenticates as user `"u1"`; anything else (including
  no header at all) is anonymous. This is a toy resolver for the example only —
  a real host verifies a signed token, session, or API key here.
  """
  @spec user_from_conn(Plug.Conn.t()) :: User.t()
  def user_from_conn(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer secret"] -> %User{id: "u1", authenticated?: true}
      _ -> User.anonymous()
    end
  end

  @doc """
  The richer card served by `GetExtendedAgentCard` to an authenticated caller.
  Returns `nil` for an anonymous user, which the SDK turns into the same error
  an unauthenticated `GetExtendedAgentCard` call gets on any server that
  doesn't support extended cards.
  """
  @spec extended_card(User.t()) :: AgentCard.t() | nil
  def extended_card(%User{authenticated?: true}) do
    %AgentCard{
      name: "Client Test Agent (extended)",
      description: "The authenticated extended card, only visible to a resolved caller.",
      version: "0.1.0",
      default_input_modes: ["text/plain"],
      default_output_modes: ["text/plain"],
      capabilities: %AgentCapabilities{streaming: true, extended_agent_card: true},
      supported_interfaces: ClientServer.Agent.agent_card().supported_interfaces,
      skills: [
        %AgentSkill{
          id: "echo",
          name: "Echo",
          description: "Returns the input text prefixed with \"echo: \".",
          tags: ["demo", "extended"]
        },
        %AgentSkill{
          id: "secret",
          name: "Secret",
          description: "A skill only visible to authenticated callers.",
          tags: ["demo", "extended"]
        }
      ]
    }
  end

  def extended_card(%User{}), do: nil
end
