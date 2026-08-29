defmodule A2A.Types.TaskStatus do
  @moduledoc "The status of a task: its state, an optional message, and a timestamp."
  alias A2A.Types.{Field, Message}

  @type t :: %__MODULE__{
          state: A2A.Types.Enums.task_state() | nil,
          message: Message.t() | nil,
          timestamp: DateTime.t() | nil
        }

  defstruct [:state, :message, :timestamp]

  @doc false
  def __a2a_proto_name__, do: "TaskStatus"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :state, proto_name: "state", number: 1, type: {:enum, :task_state}),
      Field.new(name: :message, proto_name: "message", number: 2, type: {:message, Message}),
      Field.new(name: :timestamp, proto_name: "timestamp", number: 3, type: :timestamp)
    ]
  end
end
