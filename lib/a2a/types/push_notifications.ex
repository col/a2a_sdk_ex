defmodule A2A.Types.TaskPushNotificationConfig do
  @moduledoc "Associates a push-notification configuration with a specific task."
  alias A2A.Types.{AuthenticationInfo, Field}

  @type t :: %__MODULE__{
          tenant: String.t() | nil,
          id: String.t() | nil,
          task_id: String.t() | nil,
          url: String.t() | nil,
          token: String.t() | nil,
          authentication: AuthenticationInfo.t() | nil
        }
  defstruct [:tenant, :id, :task_id, :url, :token, :authentication]

  @doc false
  def __a2a_proto_name__, do: "TaskPushNotificationConfig"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :tenant, proto_name: "tenant", number: 1, type: :string),
      Field.new(name: :id, proto_name: "id", number: 2, type: :string),
      Field.new(name: :task_id, proto_name: "task_id", number: 3, type: :string),
      Field.new(name: :url, proto_name: "url", number: 4, type: :string),
      Field.new(name: :token, proto_name: "token", number: 5, type: :string),
      Field.new(
        name: :authentication,
        proto_name: "authentication",
        number: 6,
        type: {:message, AuthenticationInfo}
      )
    ]
  end
end

defmodule A2A.Types.GetTaskPushNotificationConfigRequest do
  @moduledoc "Request to fetch a task's push-notification configuration by id."
  alias A2A.Types.Field

  @type t :: %__MODULE__{tenant: String.t() | nil, task_id: String.t() | nil, id: String.t() | nil}
  defstruct [:tenant, :task_id, :id]

  @doc false
  def __a2a_proto_name__, do: "GetTaskPushNotificationConfigRequest"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :tenant, proto_name: "tenant", number: 1, type: :string),
      Field.new(name: :task_id, proto_name: "task_id", number: 2, type: :string),
      Field.new(name: :id, proto_name: "id", number: 3, type: :string)
    ]
  end
end

defmodule A2A.Types.DeleteTaskPushNotificationConfigRequest do
  @moduledoc "Request to delete a task's push-notification configuration by id."
  alias A2A.Types.Field

  @type t :: %__MODULE__{tenant: String.t() | nil, task_id: String.t() | nil, id: String.t() | nil}
  defstruct [:tenant, :task_id, :id]

  @doc false
  def __a2a_proto_name__, do: "DeleteTaskPushNotificationConfigRequest"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :tenant, proto_name: "tenant", number: 1, type: :string),
      Field.new(name: :task_id, proto_name: "task_id", number: 2, type: :string),
      Field.new(name: :id, proto_name: "id", number: 3, type: :string)
    ]
  end
end

defmodule A2A.Types.ListTaskPushNotificationConfigsRequest do
  @moduledoc "Request to list a task's push-notification configurations."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          task_id: String.t() | nil,
          page_size: integer() | nil,
          page_token: String.t() | nil,
          tenant: String.t() | nil
        }
  defstruct [:task_id, :page_size, :page_token, :tenant]

  @doc false
  def __a2a_proto_name__, do: "ListTaskPushNotificationConfigsRequest"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    # NOTE: proto field numbers are NOT in positional order (tenant is #4).
    [
      Field.new(name: :task_id, proto_name: "task_id", number: 1, type: :string),
      Field.new(name: :page_size, proto_name: "page_size", number: 2, type: :int32),
      Field.new(name: :page_token, proto_name: "page_token", number: 3, type: :string),
      Field.new(name: :tenant, proto_name: "tenant", number: 4, type: :string)
    ]
  end
end

defmodule A2A.Types.ListTaskPushNotificationConfigsResponse do
  @moduledoc "Response listing a task's push-notification configurations."
  alias A2A.Types.{Field, TaskPushNotificationConfig}

  @type t :: %__MODULE__{
          configs: [TaskPushNotificationConfig.t()],
          next_page_token: String.t() | nil
        }
  defstruct configs: [], next_page_token: nil

  @doc false
  def __a2a_proto_name__, do: "ListTaskPushNotificationConfigsResponse"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :configs,
        proto_name: "configs",
        number: 1,
        type: {:message, TaskPushNotificationConfig},
        cardinality: :repeated
      ),
      Field.new(name: :next_page_token, proto_name: "next_page_token", number: 2, type: :string)
    ]
  end
end
