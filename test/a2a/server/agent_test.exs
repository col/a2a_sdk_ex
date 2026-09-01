defmodule A2A.Server.AgentTest do
  use ExUnit.Case, async: true

  alias A2A.Types.{AgentCard, AgentInterface, AgentSkill}

  defmodule Minimal do
    use A2A.Server.Agent, name: "min", description: "d", version: "1.0.0"

    @impl A2A.Server.Agent
    def handle_message(_ctx), do: reply() |> artifact("a", "ok")
  end

  defmodule Custom do
    use A2A.Server.Agent,
      name: "custom",
      version: "2.0.0",
      skills: [%{id: "s1", name: "Skill One", tags: ["x"]}]

    @impl A2A.Server.Agent
    def handle_message(_ctx), do: reply()

    @impl A2A.Server.Agent
    def skills(default), do: default ++ [%AgentSkill{id: "s2", name: "Added"}]

    @impl A2A.Server.Agent
    def agent_card(card), do: %{card | description: "overridden"}

    @impl A2A.Server.AgentExecutor
    def cancel(_ctx, updater) do
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      A2A.Server.TaskUpdater.update_status(updater, :rejected)
      :ok
    end
  end

  test "the macro generates an AgentExecutor with both callbacks" do
    assert function_exported?(Minimal, :execute, 2)
    assert function_exported?(Minimal, :cancel, 2)
    behaviours = Minimal.module_info(:attributes)[:behaviour]
    assert A2A.Server.AgentExecutor in behaviours
  end

  test "agent_card/0 builds a card with sensible defaults" do
    card = Minimal.agent_card()
    assert %AgentCard{name: "min", version: "1.0.0", description: "d"} = card
    assert card.capabilities.streaming == true
    assert card.default_input_modes == ["text/plain"]

    assert [
             %AgentInterface{protocol_binding: "JSONRPC", url: nil},
             %AgentInterface{protocol_binding: "HTTP+JSON", url: nil}
           ] = card.supported_interfaces
  end

  test "skills/1 runs before agent_card/1 and both compose" do
    card = Custom.agent_card()
    assert card.description == "overridden"

    assert [%AgentSkill{id: "s1", name: "Skill One", tags: ["x"]}, %AgentSkill{id: "s2"}] =
             card.skills
  end

  test "lightweight skill map missing :id raises" do
    assert_raise ArgumentError, ~r/:id/, fn ->
      A2A.Server.Agent.build_card([skills: [%{name: "no id"}]], Minimal)
    end
  end
end
