defmodule A2A.Types.TaskStatusUpdateEvent do
  @moduledoc "Streaming event: a task's status changed."
  alias A2A.Types.{Field, TaskStatus}

  @type t :: %__MODULE__{
          task_id: String.t() | nil,
          context_id: String.t() | nil,
          status: TaskStatus.t() | nil,
          metadata: map() | nil
        }
  defstruct [:task_id, :context_id, :status, :metadata]

  @doc false
  def __a2a_proto_name__, do: "TaskStatusUpdateEvent"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :task_id, proto_name: "task_id", number: 1, type: :string),
      Field.new(name: :context_id, proto_name: "context_id", number: 2, type: :string),
      Field.new(name: :status, proto_name: "status", number: 3, type: {:message, TaskStatus}),
      Field.new(name: :metadata, proto_name: "metadata", number: 4, type: :struct)
    ]
  end
end

defmodule A2A.Types.TaskArtifactUpdateEvent do
  @moduledoc "Streaming event: an artifact was produced or appended."
  alias A2A.Types.{Artifact, Field}

  @type t :: %__MODULE__{
          task_id: String.t() | nil,
          context_id: String.t() | nil,
          artifact: Artifact.t() | nil,
          append: boolean() | nil,
          last_chunk: boolean() | nil,
          metadata: map() | nil
        }
  defstruct [:task_id, :context_id, :artifact, :append, :last_chunk, :metadata]

  @doc false
  def __a2a_proto_name__, do: "TaskArtifactUpdateEvent"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :task_id, proto_name: "task_id", number: 1, type: :string),
      Field.new(name: :context_id, proto_name: "context_id", number: 2, type: :string),
      Field.new(name: :artifact, proto_name: "artifact", number: 3, type: {:message, Artifact}),
      Field.new(name: :append, proto_name: "append", number: 4, type: :bool),
      Field.new(name: :last_chunk, proto_name: "last_chunk", number: 5, type: :bool),
      Field.new(name: :metadata, proto_name: "metadata", number: 6, type: :struct)
    ]
  end
end

defmodule A2A.Types.StreamResponse do
  @moduledoc "A streamed response frame: one of task | message | status_update | artifact_update."
  alias A2A.Types.{Field, Message, Task, TaskArtifactUpdateEvent, TaskStatusUpdateEvent}

  @type kind :: :task | :message | :status_update | :artifact_update
  @type t :: %__MODULE__{
          kind: kind,
          task: Task.t() | nil,
          message: Message.t() | nil,
          status_update: TaskStatusUpdateEvent.t() | nil,
          artifact_update: TaskArtifactUpdateEvent.t() | nil
        }
  defstruct [:kind, :task, :message, :status_update, :artifact_update]

  @spec task(Task.t()) :: t
  def task(%Task{} = t), do: %__MODULE__{kind: :task, task: t}
  @spec message(Message.t()) :: t
  def message(%Message{} = m), do: %__MODULE__{kind: :message, message: m}
  @spec status_update(TaskStatusUpdateEvent.t()) :: t
  def status_update(%TaskStatusUpdateEvent{} = e),
    do: %__MODULE__{kind: :status_update, status_update: e}

  @spec artifact_update(TaskArtifactUpdateEvent.t()) :: t
  def artifact_update(%TaskArtifactUpdateEvent{} = e),
    do: %__MODULE__{kind: :artifact_update, artifact_update: e}

  @doc false
  def __a2a_proto_name__, do: "StreamResponse"
  @doc false
  def __a2a_discriminator__, do: :kind

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :task,
        proto_name: "task",
        number: 1,
        type: {:message, Task},
        presence: :explicit,
        oneof: {:payload, :task}
      ),
      Field.new(
        name: :message,
        proto_name: "message",
        number: 2,
        type: {:message, Message},
        presence: :explicit,
        oneof: {:payload, :message}
      ),
      Field.new(
        name: :status_update,
        proto_name: "status_update",
        number: 3,
        type: {:message, TaskStatusUpdateEvent},
        presence: :explicit,
        oneof: {:payload, :status_update}
      ),
      Field.new(
        name: :artifact_update,
        proto_name: "artifact_update",
        number: 4,
        type: {:message, TaskArtifactUpdateEvent},
        presence: :explicit,
        oneof: {:payload, :artifact_update}
      )
    ]
  end
end
