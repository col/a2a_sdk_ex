defmodule A2A.Types.Message do
  @moduledoc "An A2A message: an ordered list of `Part`s with a role."
  alias A2A.Types.{Field, Part}

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          context_id: String.t() | nil,
          task_id: String.t() | nil,
          role: A2A.Types.Enums.role() | nil,
          parts: [Part.t()],
          metadata: map() | nil,
          extensions: [String.t()],
          reference_task_ids: [String.t()]
        }

  defstruct [
    :message_id,
    :context_id,
    :task_id,
    :role,
    :metadata,
    parts: [],
    extensions: [],
    reference_task_ids: []
  ]

  @doc false
  def __a2a_proto_name__, do: "Message"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :message_id, proto_name: "message_id", number: 1, type: :string),
      Field.new(name: :context_id, proto_name: "context_id", number: 2, type: :string),
      Field.new(name: :task_id, proto_name: "task_id", number: 3, type: :string),
      Field.new(name: :role, proto_name: "role", number: 4, type: {:enum, :role}),
      Field.new(
        name: :parts,
        proto_name: "parts",
        number: 5,
        type: {:message, Part},
        cardinality: :repeated
      ),
      Field.new(name: :metadata, proto_name: "metadata", number: 6, type: :struct),
      Field.new(
        name: :extensions,
        proto_name: "extensions",
        number: 7,
        type: :string,
        cardinality: :repeated
      ),
      Field.new(
        name: :reference_task_ids,
        proto_name: "reference_task_ids",
        number: 8,
        type: :string,
        cardinality: :repeated
      )
    ]
  end
end
