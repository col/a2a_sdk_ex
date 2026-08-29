defmodule A2A.Types.StringList do
  @moduledoc "A list of strings (proto `StringList`; used as OAuth-scope map values)."
  alias A2A.Types.Field

  @type t :: %__MODULE__{list: [String.t()]}
  defstruct list: []

  @doc false
  def __a2a_proto_name__, do: "StringList"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [Field.new(name: :list, proto_name: "list", number: 1, type: :string, cardinality: :repeated)]
  end
end

defmodule A2A.Types.SecurityRequirement do
  @moduledoc "A map of security-scheme name to the required scopes."
  alias A2A.Types.{Field, StringList}

  @type t :: %__MODULE__{schemes: %{optional(String.t()) => StringList.t()}}
  defstruct schemes: %{}

  @doc false
  def __a2a_proto_name__, do: "SecurityRequirement"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :schemes,
        proto_name: "schemes",
        number: 1,
        type: {:map, :string, {:message, StringList}}
      )
    ]
  end
end
