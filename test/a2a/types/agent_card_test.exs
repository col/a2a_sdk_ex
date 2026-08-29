defmodule A2A.Types.AgentCardTest do
  use ExUnit.Case, async: true

  alias A2A.JSON

  alias A2A.Types.{
    AgentCapabilities,
    AgentCard,
    AgentCardSignature,
    AgentExtension,
    AgentInterface,
    AgentProvider,
    AgentSkill,
    GetExtendedAgentCardRequest
  }

  test "AgentInterface struct + field spec" do
    assert %AgentInterface{url: nil, protocol_binding: nil, tenant: nil, protocol_version: nil} =
             %AgentInterface{}

    by_name = Map.new(AgentInterface.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "url", number: 1, type: :string, cardinality: :singular} = by_name.url

    assert %{proto_name: "protocol_binding", number: 2, type: :string} = by_name.protocol_binding

    assert %{proto_name: "tenant", number: 3, type: :string} = by_name.tenant
    assert %{proto_name: "protocol_version", number: 4, type: :string} = by_name.protocol_version
    assert AgentInterface.__a2a_proto_name__() == "AgentInterface"
  end

  test "AgentProvider struct + field spec" do
    assert %AgentProvider{url: nil, organization: nil} = %AgentProvider{}

    by_name = Map.new(AgentProvider.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "url", number: 1, type: :string} = by_name.url
    assert %{proto_name: "organization", number: 2, type: :string} = by_name.organization
    assert AgentProvider.__a2a_proto_name__() == "AgentProvider"
  end

  test "AgentExtension struct + field spec" do
    assert %AgentExtension{uri: nil, description: nil, required: nil, params: nil} =
             %AgentExtension{}

    by_name = Map.new(AgentExtension.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "uri", number: 1, type: :string} = by_name.uri
    assert %{proto_name: "description", number: 2, type: :string} = by_name.description
    assert %{proto_name: "required", number: 3, type: :bool} = by_name.required
    assert %{proto_name: "params", number: 4, type: :struct} = by_name.params
    assert AgentExtension.__a2a_proto_name__() == "AgentExtension"
  end

  test "AgentCapabilities struct + field spec" do
    assert %AgentCapabilities{
             streaming: nil,
             push_notifications: nil,
             extensions: [],
             extended_agent_card: nil
           } = %AgentCapabilities{}

    by_name = Map.new(AgentCapabilities.__a2a_fields__(), &{&1.name, &1})

    assert %{proto_name: "streaming", number: 1, type: :bool, presence: :explicit} =
             by_name.streaming

    assert %{proto_name: "push_notifications", number: 2, type: :bool, presence: :explicit} =
             by_name.push_notifications

    assert %{
             proto_name: "extensions",
             number: 3,
             type: {:message, AgentExtension},
             cardinality: :repeated
           } = by_name.extensions

    assert %{proto_name: "extended_agent_card", number: 4, type: :bool, presence: :explicit} =
             by_name.extended_agent_card

    assert AgentCapabilities.__a2a_proto_name__() == "AgentCapabilities"
  end

  test "AgentSkill struct + field spec" do
    assert %AgentSkill{
             id: nil,
             name: nil,
             description: nil,
             tags: [],
             examples: [],
             input_modes: [],
             output_modes: [],
             security_requirements: []
           } = %AgentSkill{}

    by_name = Map.new(AgentSkill.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "id", number: 1, type: :string} = by_name.id
    assert %{proto_name: "name", number: 2, type: :string} = by_name.name
    assert %{proto_name: "description", number: 3, type: :string} = by_name.description

    assert %{proto_name: "tags", number: 4, type: :string, cardinality: :repeated} = by_name.tags

    assert %{proto_name: "examples", number: 5, type: :string, cardinality: :repeated} =
             by_name.examples

    assert %{proto_name: "input_modes", number: 6, type: :string, cardinality: :repeated} =
             by_name.input_modes

    assert %{proto_name: "output_modes", number: 7, type: :string, cardinality: :repeated} =
             by_name.output_modes

    assert %{
             proto_name: "security_requirements",
             number: 8,
             type: :raw,
             cardinality: :repeated
           } = by_name.security_requirements

    assert AgentSkill.__a2a_proto_name__() == "AgentSkill"
  end

  test "AgentCardSignature struct + field spec" do
    assert %AgentCardSignature{protected: nil, signature: nil, header: nil} = %AgentCardSignature{}

    by_name = Map.new(AgentCardSignature.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "protected", number: 1, type: :string} = by_name.protected
    assert %{proto_name: "signature", number: 2, type: :string} = by_name.signature
    assert %{proto_name: "header", number: 3, type: :struct} = by_name.header
    assert AgentCardSignature.__a2a_proto_name__() == "AgentCardSignature"
  end

  test "AgentCard struct + field spec" do
    assert %AgentCard{
             name: nil,
             description: nil,
             supported_interfaces: [],
             provider: nil,
             version: nil,
             documentation_url: nil,
             capabilities: nil,
             security_schemes: nil,
             security_requirements: [],
             default_input_modes: [],
             default_output_modes: [],
             skills: [],
             signatures: [],
             icon_url: nil
           } = %AgentCard{}

    by_name = Map.new(AgentCard.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "name", number: 1, type: :string} = by_name.name
    assert %{proto_name: "description", number: 2, type: :string} = by_name.description

    assert %{
             proto_name: "supported_interfaces",
             number: 3,
             type: {:message, AgentInterface},
             cardinality: :repeated
           } = by_name.supported_interfaces

    assert %{proto_name: "provider", number: 4, type: {:message, AgentProvider}} = by_name.provider

    assert %{proto_name: "version", number: 5, type: :string} = by_name.version

    assert %{proto_name: "documentation_url", number: 6, type: :string, presence: :explicit} =
             by_name.documentation_url

    assert %{proto_name: "capabilities", number: 7, type: {:message, AgentCapabilities}} =
             by_name.capabilities

    assert %{proto_name: "security_schemes", number: 8, type: :raw, cardinality: :singular} =
             by_name.security_schemes

    assert %{
             proto_name: "security_requirements",
             number: 9,
             type: :raw,
             cardinality: :repeated
           } = by_name.security_requirements

    assert %{
             proto_name: "default_input_modes",
             number: 10,
             type: :string,
             cardinality: :repeated
           } = by_name.default_input_modes

    assert %{
             proto_name: "default_output_modes",
             number: 11,
             type: :string,
             cardinality: :repeated
           } = by_name.default_output_modes

    assert %{
             proto_name: "skills",
             number: 12,
             type: {:message, AgentSkill},
             cardinality: :repeated
           } = by_name.skills

    assert %{
             proto_name: "signatures",
             number: 13,
             type: {:message, AgentCardSignature},
             cardinality: :repeated
           } = by_name.signatures

    assert %{proto_name: "icon_url", number: 14, type: :string, presence: :explicit} =
             by_name.icon_url

    assert AgentCard.__a2a_proto_name__() == "AgentCard"
  end

  test "GetExtendedAgentCardRequest struct + field spec" do
    assert %GetExtendedAgentCardRequest{tenant: nil} = %GetExtendedAgentCardRequest{}

    by_name = Map.new(GetExtendedAgentCardRequest.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "tenant", number: 1, type: :string} = by_name.tenant
    assert GetExtendedAgentCardRequest.__a2a_proto_name__() == "GetExtendedAgentCardRequest"
  end

  test "round-trips a populated AgentCard through encode |> decode" do
    card = %AgentCard{
      name: "Weather Agent",
      description: "Provides weather forecasts",
      supported_interfaces: [
        %AgentInterface{
          url: "https://example.com/a2a",
          protocol_binding: "JSONRPC",
          tenant: "acme",
          protocol_version: "1.0"
        }
      ],
      provider: %AgentProvider{url: "https://example.com", organization: "Example Corp"},
      version: "1.0.0",
      documentation_url: "https://example.com/docs",
      capabilities: %AgentCapabilities{
        streaming: true,
        push_notifications: false,
        extensions: [
          %AgentExtension{
            uri: "https://example.com/ext",
            description: "An extension",
            required: true,
            params: %{"key" => "value"}
          }
        ],
        extended_agent_card: true
      },
      security_schemes: nil,
      security_requirements: [],
      default_input_modes: ["text/plain"],
      default_output_modes: ["text/plain"],
      skills: [
        %AgentSkill{
          id: "forecast",
          name: "Forecast",
          description: "Gives a forecast",
          tags: ["weather"],
          examples: ["What's the weather?"],
          input_modes: ["text/plain"],
          output_modes: ["text/plain"],
          security_requirements: []
        }
      ],
      signatures: [
        %AgentCardSignature{
          protected: "protected-header",
          signature: "sig",
          header: %{"alg" => "RS256"}
        }
      ],
      icon_url: "https://example.com/icon.png"
    }

    {:ok, iodata} = JSON.encode(card)
    assert {:ok, ^card} = JSON.decode(IO.iodata_to_binary(iodata), AgentCard)
  end

  test "explicit-presence optional string distinguishes set-empty from unset" do
    set_empty = %AgentCard{documentation_url: ""}
    json = set_empty |> JSON.encode!() |> Jason.decode!()

    assert Map.has_key?(json, "documentationUrl")
    assert json["documentationUrl"] == ""
    assert {:ok, %AgentCard{documentation_url: ""}} = JSON.decode(Jason.encode!(json), AgentCard)

    unset = %AgentCard{documentation_url: nil}
    json = unset |> JSON.encode!() |> Jason.decode!()

    refute Map.has_key?(json, "documentationUrl")
    assert {:ok, %AgentCard{documentation_url: nil}} = JSON.decode(Jason.encode!(json), AgentCard)
  end
end
