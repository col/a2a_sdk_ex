defmodule A2A.Server.Events do
  @moduledoc false
  alias A2A.Types.{Message, Task, TaskArtifactUpdateEvent, TaskStatusUpdateEvent}

  defmodule Event do
    @moduledoc "One frame on a task topic. `terminal?` marks the end of the blocking drain."
    @type payload ::
            Task.t() | Message.t() | TaskStatusUpdateEvent.t() | TaskArtifactUpdateEvent.t()
    @type t :: %__MODULE__{
            task_id: String.t(),
            context_id: String.t() | nil,
            payload: payload(),
            terminal?: boolean()
          }
    defstruct [:task_id, :context_id, :payload, terminal?: false]
  end

  @spec topic(String.t()) :: String.t()
  def topic(task_id), do: "a2a:task:" <> task_id

  @spec subscribe(atom(), String.t()) :: :ok
  def subscribe(pubsub, task_id), do: Phoenix.PubSub.subscribe(pubsub, topic(task_id))

  @spec unsubscribe(atom(), String.t()) :: :ok
  def unsubscribe(pubsub, task_id), do: Phoenix.PubSub.unsubscribe(pubsub, topic(task_id))

  @spec broadcast(atom(), Event.t()) :: :ok
  def broadcast(pubsub, %Event{task_id: task_id} = event),
    do: Phoenix.PubSub.broadcast(pubsub, topic(task_id), event)
end
