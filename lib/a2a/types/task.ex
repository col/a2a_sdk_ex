defmodule A2A.Types.Task do
  @moduledoc "An A2A task: an id, its status, and accumulated artifacts/history."
  alias A2A.Types.{Artifact, Field, Message, TaskStatus}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          context_id: String.t() | nil,
          status: TaskStatus.t() | nil,
          artifacts: [Artifact.t()],
          history: [Message.t()],
          metadata: map() | nil
        }

  defstruct [:id, :context_id, :status, :metadata, artifacts: [], history: []]

  @doc false
  def __a2a_proto_name__, do: "Task"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :id, proto_name: "id", number: 1, type: :string),
      Field.new(name: :context_id, proto_name: "context_id", number: 2, type: :string),
      Field.new(name: :status, proto_name: "status", number: 3, type: {:message, TaskStatus}),
      Field.new(
        name: :artifacts,
        proto_name: "artifacts",
        number: 4,
        type: {:message, Artifact},
        cardinality: :repeated
      ),
      Field.new(
        name: :history,
        proto_name: "history",
        number: 5,
        type: {:message, Message},
        cardinality: :repeated
      ),
      Field.new(name: :metadata, proto_name: "metadata", number: 6, type: :struct)
    ]
  end
end
