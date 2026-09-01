defmodule A2A.Server.Agent do
  @moduledoc """
  Ergonomic, runtime-style layer over `A2A.Server.AgentExecutor`.

  `use A2A.Server.Agent` generates an `AgentExecutor` whose `execute/2` runs your
  `handle_message/1` and folds its `A2A.Server.Agent.Result` through
  `A2A.Server.Agent.Interpreter`. It also derives an `A2A.Types.AgentCard` from
  the `use` options, customizable via the overridable `skills/1` (runs first) and
  `agent_card/1` callbacks. Need raw imperative control? Skip the macro and
  implement `A2A.Server.AgentExecutor` directly — the two layers coexist.

      defmodule MyAgent do
        use A2A.Server.Agent, name: "my-agent", description: "Does things"

        @impl A2A.Server.Agent
        def handle_message(ctx) do
          reply() |> artifact("answer", "echo: " <> A2A.Server.RequestContext.user_input(ctx))
        end
      end
  """
  alias A2A.Server.Agent.Result
  alias A2A.Server.RequestContext
  alias A2A.Types.{AgentCapabilities, AgentCard, AgentInterface, AgentSkill}

  @callback handle_message(RequestContext.t()) :: Result.t()
  @callback skills([AgentSkill.t()]) :: [AgentSkill.t()]
  @callback agent_card(AgentCard.t()) :: AgentCard.t()
  @optional_callbacks skills: 1, agent_card: 1

  defmacro __using__(opts) do
    quote do
      @behaviour A2A.Server.AgentExecutor
      @behaviour A2A.Server.Agent

      import A2A.Server.Agent.Result

      @a2a_card_opts unquote(opts)

      @impl A2A.Server.AgentExecutor
      def execute(ctx, updater) do
        ctx
        |> handle_message()
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        |> A2A.Server.Agent.Interpreter.run(updater)

        :ok
      end

      @impl A2A.Server.AgentExecutor
      def cancel(_ctx, updater) do
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        A2A.Server.TaskUpdater.update_status(updater, :canceled)
        :ok
      end

      @impl A2A.Server.Agent
      def skills(default), do: default

      @impl A2A.Server.Agent
      def agent_card(card), do: card

      @doc "The `AgentCard` derived from the `use` options and callbacks."
      def agent_card, do: A2A.Server.Agent.build_card(@a2a_card_opts, __MODULE__)

      defoverridable cancel: 2, skills: 1, agent_card: 1
    end
  end

  @doc """
  Builds the default `AgentCard` from `use` options, runs `module.skills/1` then
  `module.agent_card/1`. Every card field is accepted as an option; omitted
  fields get sensible defaults.
  """
  @spec build_card(keyword(), module()) :: AgentCard.t()
  def build_card(opts, module) do
    skills = opts |> Keyword.get(:skills, []) |> Enum.map(&build_skill/1) |> module.skills()

    %AgentCard{
      name: Keyword.get(opts, :name),
      description: Keyword.get(opts, :description),
      version: Keyword.get(opts, :version),
      provider: Keyword.get(opts, :provider),
      documentation_url: Keyword.get(opts, :documentation_url),
      icon_url: Keyword.get(opts, :icon_url),
      security_schemes: Keyword.get(opts, :security_schemes),
      security_requirements: Keyword.get(opts, :security_requirements, []),
      default_input_modes: Keyword.get(opts, :default_input_modes, ["text/plain"]),
      default_output_modes: Keyword.get(opts, :default_output_modes, ["text/plain"]),
      capabilities: Keyword.get(opts, :capabilities, %AgentCapabilities{streaming: true}),
      supported_interfaces: Keyword.get(opts, :supported_interfaces, default_interfaces()),
      skills: skills
    }
    |> module.agent_card()
  end

  defp default_interfaces do
    [
      %AgentInterface{protocol_binding: "JSONRPC", protocol_version: "1.0"},
      %AgentInterface{protocol_binding: "HTTP+JSON", protocol_version: "1.0"}
    ]
  end

  defp build_skill(%AgentSkill{} = skill), do: skill

  defp build_skill(map) when is_map(map) do
    %AgentSkill{
      id: fetch_skill!(map, :id),
      name: fetch_skill!(map, :name),
      description: Map.get(map, :description),
      tags: Map.get(map, :tags, []),
      examples: Map.get(map, :examples, []),
      input_modes: Map.get(map, :input_modes, []),
      output_modes: Map.get(map, :output_modes, [])
    }
  end

  defp fetch_skill!(map, key) do
    Map.get(map, key) || raise ArgumentError, "agent skill requires #{inspect(key)}"
  end
end
