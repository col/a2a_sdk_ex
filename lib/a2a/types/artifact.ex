defmodule A2A.Types.Artifact do
  @moduledoc "An artifact produced by a task: named, described, a list of `Part`s."
  alias A2A.Types.{Field, Part}

  @type t :: %__MODULE__{
          artifact_id: String.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          parts: [Part.t()],
          metadata: map() | nil,
          extensions: [String.t()]
        }

  defstruct [:artifact_id, :name, :description, :metadata, parts: [], extensions: []]

  @doc false
  def __a2a_proto_name__, do: "Artifact"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :artifact_id, proto_name: "artifact_id", number: 1, type: :string),
      Field.new(name: :name, proto_name: "name", number: 2, type: :string),
      Field.new(name: :description, proto_name: "description", number: 3, type: :string),
      Field.new(
        name: :parts,
        proto_name: "parts",
        number: 4,
        type: {:message, Part},
        cardinality: :repeated
      ),
      Field.new(name: :metadata, proto_name: "metadata", number: 5, type: :struct),
      Field.new(
        name: :extensions,
        proto_name: "extensions",
        number: 6,
        type: :string,
        cardinality: :repeated
      )
    ]
  end
end
