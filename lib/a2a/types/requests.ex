defmodule A2A.Types.SendMessageConfiguration do
  @moduledoc "Per-request send configuration."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          accepted_output_modes: [String.t()],
          task_push_notification_config: map() | nil,
          history_length: integer() | nil,
          return_immediately: boolean() | nil
        }
  defstruct [
    :task_push_notification_config,
    :history_length,
    :return_immediately,
    accepted_output_modes: []
  ]

  @doc false
  def __a2a_proto_name__, do: "SendMessageConfiguration"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :accepted_output_modes,
        proto_name: "accepted_output_modes",
        number: 1,
        type: :string,
        cardinality: :repeated
      ),
      # task_push_notification_config references a Phase-4 message; passthrough until Phase 4 builds the struct.
      Field.new(
        name: :task_push_notification_config,
        proto_name: "task_push_notification_config",
        number: 2,
        type: :raw
      ),
      Field.new(
        name: :history_length,
        proto_name: "history_length",
        number: 3,
        type: :int32,
        presence: :explicit
      ),
      Field.new(name: :return_immediately, proto_name: "return_immediately", number: 4, type: :bool)
    ]
  end
end

defmodule A2A.Types.SendMessageRequest do
  @moduledoc "Request to send a message to an agent."
  alias A2A.Types.{Field, Message, SendMessageConfiguration}

  @type t :: %__MODULE__{
          tenant: String.t() | nil,
          message: Message.t() | nil,
          configuration: SendMessageConfiguration.t() | nil,
          metadata: map() | nil
        }
  defstruct [:tenant, :message, :configuration, :metadata]

  @doc false
  def __a2a_proto_name__, do: "SendMessageRequest"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :tenant, proto_name: "tenant", number: 1, type: :string),
      Field.new(name: :message, proto_name: "message", number: 2, type: {:message, Message}),
      Field.new(
        name: :configuration,
        proto_name: "configuration",
        number: 3,
        type: {:message, SendMessageConfiguration}
      ),
      Field.new(name: :metadata, proto_name: "metadata", number: 4, type: :struct)
    ]
  end
end

defmodule A2A.Types.SendMessageResponse do
  @moduledoc "Response to a send: one of task | message."
  alias A2A.Types.{Field, Message, Task}

  @type kind :: :task | :message
  @type t :: %__MODULE__{kind: kind, task: Task.t() | nil, message: Message.t() | nil}
  defstruct [:kind, :task, :message]

  @spec task(Task.t()) :: t
  def task(%Task{} = t), do: %__MODULE__{kind: :task, task: t}
  @spec message(Message.t()) :: t
  def message(%Message{} = m), do: %__MODULE__{kind: :message, message: m}

  @doc false
  def __a2a_proto_name__, do: "SendMessageResponse"
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
      )
    ]
  end
end

defmodule A2A.Types.GetTaskRequest do
  @moduledoc "Request to fetch a task by id."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          tenant: String.t() | nil,
          id: String.t() | nil,
          history_length: integer() | nil
        }
  defstruct [:tenant, :id, :history_length]

  @doc false
  def __a2a_proto_name__, do: "GetTaskRequest"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :tenant, proto_name: "tenant", number: 1, type: :string),
      Field.new(name: :id, proto_name: "id", number: 2, type: :string),
      Field.new(
        name: :history_length,
        proto_name: "history_length",
        number: 3,
        type: :int32,
        presence: :explicit
      )
    ]
  end
end
