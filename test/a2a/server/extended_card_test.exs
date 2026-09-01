defmodule A2A.Server.ExtendedCardTest do
  use ExUnit.Case, async: true

  alias A2A.Server
  alias A2A.Server.DefaultHandler
  alias A2A.Types.{AgentCapabilities, AgentCard}
  alias A2A.User

  defp server(card, resolver) do
    %Server{
      name: :t,
      executor: A2A.Test.EchoExecutor,
      pubsub: :p,
      scope: A2A.Scope.default(),
      user: %User{id: "alice", authenticated?: true},
      owner_resolver: fn _ -> nil end,
      agent_card: card,
      extended_agent_card_resolver: resolver
    }
  end

  @base %AgentCard{name: "Base", version: "1", default_input_modes: ["text/plain"]}
  @advertised %AgentCard{
    name: "Base",
    version: "1",
    default_input_modes: ["text/plain"],
    capabilities: %AgentCapabilities{extended_agent_card: true}
  }
  @extended %AgentCard{name: "Extended", version: "1", default_input_modes: ["text/plain"]}

  test "capability not advertised ⇒ not configured" do
    s = server(@base, fn _ -> @extended end)

    assert {:error, %A2A.Error{code: :extended_agent_card_not_configured}} =
             DefaultHandler.get_extended_agent_card(s)
  end

  test "advertised but no resolver ⇒ not configured" do
    s = server(@advertised, nil)

    assert {:error, %A2A.Error{code: :extended_agent_card_not_configured}} =
             DefaultHandler.get_extended_agent_card(s)
  end

  test "advertised, resolver returns nil ⇒ not configured" do
    s = server(@advertised, fn _ -> nil end)

    assert {:error, %A2A.Error{code: :extended_agent_card_not_configured}} =
             DefaultHandler.get_extended_agent_card(s)
  end

  test "advertised + resolver returns a card ⇒ that card, passed the caller" do
    s = server(@advertised, fn %User{id: id} -> %{@extended | name: "for-" <> id} end)
    assert {:ok, %AgentCard{name: "for-alice"}} = DefaultHandler.get_extended_agent_card(s)
  end
end
