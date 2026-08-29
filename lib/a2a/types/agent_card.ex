defmodule A2A.Types.AgentInterface do
  @moduledoc "A transport binding at which an agent is reachable."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          url: String.t() | nil,
          protocol_binding: String.t() | nil,
          tenant: String.t() | nil,
          protocol_version: String.t() | nil
        }
  defstruct [:url, :protocol_binding, :tenant, :protocol_version]

  @doc false
  def __a2a_proto_name__, do: "AgentInterface"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :url, proto_name: "url", number: 1, type: :string),
      Field.new(
        name: :protocol_binding,
        proto_name: "protocol_binding",
        number: 2,
        type: :string
      ),
      Field.new(name: :tenant, proto_name: "tenant", number: 3, type: :string),
      Field.new(
        name: :protocol_version,
        proto_name: "protocol_version",
        number: 4,
        type: :string
      )
    ]
  end
end

defmodule A2A.Types.AgentProvider do
  @moduledoc "The organization that provides an agent."
  alias A2A.Types.Field

  @type t :: %__MODULE__{url: String.t() | nil, organization: String.t() | nil}
  defstruct [:url, :organization]

  @doc false
  def __a2a_proto_name__, do: "AgentProvider"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :url, proto_name: "url", number: 1, type: :string),
      Field.new(name: :organization, proto_name: "organization", number: 2, type: :string)
    ]
  end
end

defmodule A2A.Types.AgentExtension do
  @moduledoc "A protocol extension an agent supports."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          uri: String.t() | nil,
          description: String.t() | nil,
          required: boolean() | nil,
          params: map() | nil
        }
  defstruct [:uri, :description, :required, :params]

  @doc false
  def __a2a_proto_name__, do: "AgentExtension"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :uri, proto_name: "uri", number: 1, type: :string),
      Field.new(name: :description, proto_name: "description", number: 2, type: :string),
      Field.new(name: :required, proto_name: "required", number: 3, type: :bool),
      Field.new(name: :params, proto_name: "params", number: 4, type: :struct)
    ]
  end
end

defmodule A2A.Types.AgentCapabilities do
  @moduledoc "Optional capabilities an agent advertises support for."
  alias A2A.Types.{AgentExtension, Field}

  @type t :: %__MODULE__{
          streaming: boolean() | nil,
          push_notifications: boolean() | nil,
          extensions: [AgentExtension.t()],
          extended_agent_card: boolean() | nil
        }
  defstruct [:streaming, :push_notifications, :extended_agent_card, extensions: []]

  @doc false
  def __a2a_proto_name__, do: "AgentCapabilities"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :streaming,
        proto_name: "streaming",
        number: 1,
        type: :bool,
        presence: :explicit
      ),
      Field.new(
        name: :push_notifications,
        proto_name: "push_notifications",
        number: 2,
        type: :bool,
        presence: :explicit
      ),
      Field.new(
        name: :extensions,
        proto_name: "extensions",
        number: 3,
        type: {:message, AgentExtension},
        cardinality: :repeated
      ),
      Field.new(
        name: :extended_agent_card,
        proto_name: "extended_agent_card",
        number: 4,
        type: :bool,
        presence: :explicit
      )
    ]
  end
end

defmodule A2A.Types.AgentSkill do
  @moduledoc "A discrete capability an agent exposes."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          tags: [String.t()],
          examples: [String.t()],
          input_modes: [String.t()],
          output_modes: [String.t()],
          security_requirements: [map()]
        }
  defstruct [
    :id,
    :name,
    :description,
    tags: [],
    examples: [],
    input_modes: [],
    output_modes: [],
    security_requirements: []
  ]

  @doc false
  def __a2a_proto_name__, do: "AgentSkill"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :id, proto_name: "id", number: 1, type: :string),
      Field.new(name: :name, proto_name: "name", number: 2, type: :string),
      Field.new(name: :description, proto_name: "description", number: 3, type: :string),
      Field.new(name: :tags, proto_name: "tags", number: 4, type: :string, cardinality: :repeated),
      Field.new(
        name: :examples,
        proto_name: "examples",
        number: 5,
        type: :string,
        cardinality: :repeated
      ),
      Field.new(
        name: :input_modes,
        proto_name: "input_modes",
        number: 6,
        type: :string,
        cardinality: :repeated
      ),
      Field.new(
        name: :output_modes,
        proto_name: "output_modes",
        number: 7,
        type: :string,
        cardinality: :repeated
      ),
      # security_requirements references a Phase-3 message; passthrough until Phase 3 builds the struct.
      Field.new(
        name: :security_requirements,
        proto_name: "security_requirements",
        number: 8,
        type: :raw,
        cardinality: :repeated
      )
    ]
  end
end

defmodule A2A.Types.AgentCardSignature do
  @moduledoc "A JWS signature over an agent card."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          protected: String.t() | nil,
          signature: String.t() | nil,
          header: map() | nil
        }
  defstruct [:protected, :signature, :header]

  @doc false
  def __a2a_proto_name__, do: "AgentCardSignature"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :protected, proto_name: "protected", number: 1, type: :string),
      Field.new(name: :signature, proto_name: "signature", number: 2, type: :string),
      Field.new(name: :header, proto_name: "header", number: 3, type: :struct)
    ]
  end
end

defmodule A2A.Types.AgentCard do
  @moduledoc "An agent's self-describing card: identity, capabilities, and skills."
  alias A2A.Types.{
    AgentCapabilities,
    AgentCardSignature,
    AgentInterface,
    AgentProvider,
    AgentSkill,
    Field
  }

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          supported_interfaces: [AgentInterface.t()],
          provider: AgentProvider.t() | nil,
          version: String.t() | nil,
          documentation_url: String.t() | nil,
          capabilities: AgentCapabilities.t() | nil,
          security_schemes: map() | nil,
          security_requirements: [map()],
          default_input_modes: [String.t()],
          default_output_modes: [String.t()],
          skills: [AgentSkill.t()],
          signatures: [AgentCardSignature.t()],
          icon_url: String.t() | nil
        }
  defstruct [
    :name,
    :description,
    :provider,
    :version,
    :documentation_url,
    :capabilities,
    :security_schemes,
    :icon_url,
    supported_interfaces: [],
    security_requirements: [],
    default_input_modes: [],
    default_output_modes: [],
    skills: [],
    signatures: []
  ]

  @doc false
  def __a2a_proto_name__, do: "AgentCard"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :name, proto_name: "name", number: 1, type: :string),
      Field.new(name: :description, proto_name: "description", number: 2, type: :string),
      Field.new(
        name: :supported_interfaces,
        proto_name: "supported_interfaces",
        number: 3,
        type: {:message, AgentInterface},
        cardinality: :repeated
      ),
      Field.new(
        name: :provider,
        proto_name: "provider",
        number: 4,
        type: {:message, AgentProvider}
      ),
      Field.new(name: :version, proto_name: "version", number: 5, type: :string),
      Field.new(
        name: :documentation_url,
        proto_name: "documentation_url",
        number: 6,
        type: :string,
        presence: :explicit
      ),
      Field.new(
        name: :capabilities,
        proto_name: "capabilities",
        number: 7,
        type: {:message, AgentCapabilities}
      ),
      # security_schemes references a Phase-3 message (map<string, SecurityScheme>); passthrough until Phase 3.
      Field.new(
        name: :security_schemes,
        proto_name: "security_schemes",
        number: 8,
        type: :raw
      ),
      # security_requirements references a Phase-3 message; passthrough until Phase 3 builds the struct.
      Field.new(
        name: :security_requirements,
        proto_name: "security_requirements",
        number: 9,
        type: :raw,
        cardinality: :repeated
      ),
      Field.new(
        name: :default_input_modes,
        proto_name: "default_input_modes",
        number: 10,
        type: :string,
        cardinality: :repeated
      ),
      Field.new(
        name: :default_output_modes,
        proto_name: "default_output_modes",
        number: 11,
        type: :string,
        cardinality: :repeated
      ),
      Field.new(
        name: :skills,
        proto_name: "skills",
        number: 12,
        type: {:message, AgentSkill},
        cardinality: :repeated
      ),
      Field.new(
        name: :signatures,
        proto_name: "signatures",
        number: 13,
        type: {:message, AgentCardSignature},
        cardinality: :repeated
      ),
      Field.new(
        name: :icon_url,
        proto_name: "icon_url",
        number: 14,
        type: :string,
        presence: :explicit
      )
    ]
  end
end

defmodule A2A.Types.GetExtendedAgentCardRequest do
  @moduledoc "Request for an agent's extended card, only available after authentication."
  alias A2A.Types.Field

  @type t :: %__MODULE__{tenant: String.t() | nil}
  defstruct [:tenant]

  @doc false
  def __a2a_proto_name__, do: "GetExtendedAgentCardRequest"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :tenant, proto_name: "tenant", number: 1, type: :string)
    ]
  end
end
