defmodule A2A.Server.Events do
  @moduledoc """
  PubSub topic convention and the internal event envelope. Every executor-emitted
  event is broadcast as an `Event` on the task topic; SSE, resubscribe, and push
  delivery (later phases) are all just additional subscribers.
  """
  alias A2A.Server.ResultAssembler

  alias A2A.Types.{
    Message,
    Task,
    TaskArtifactUpdateEvent,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  defmodule Event do
    @moduledoc """
    One frame on a task topic. Whether a frame ends a stream is derived from its
    payload — see `A2A.Server.Events.final?/1` — never carried as a flag, so the
    blocking rule (§3.2.2) and the streaming rule (§3.1.2, §3.1.6) cannot drift.
    """
    @type payload ::
            Task.t() | Message.t() | TaskStatusUpdateEvent.t() | TaskArtifactUpdateEvent.t()
    @type t :: %__MODULE__{
            task_id: String.t(),
            context_id: String.t() | nil,
            payload: payload()
          }
    defstruct [:task_id, :context_id, :payload]
  end

  @doc """
  Does this payload close a stream?

  Spec §3.1.2 and §3.1.6 give both streaming operations the same rule: the stream
  ends when the task reaches a terminal state (`completed`, `failed`, `canceled`,
  `rejected`) — or, for a direct reply, after the single `Message` (§3.1.2 pattern 1).

  Interrupted states (`input_required`, `auth_required`) are deliberately NOT final:
  they end a *blocking* caller's wait (§3.2.2) while the task stays resumable and
  every attached stream stays open. That rule belongs to `A2A.Server.DefaultHandler`.
  """
  @spec final?(Event.payload()) :: boolean()
  def final?(%Message{}), do: true
  def final?(%Task{} = task), do: ResultAssembler.terminal?(task)

  def final?(%TaskStatusUpdateEvent{status: %TaskStatus{state: state}}),
    do: ResultAssembler.terminal_state?(state)

  def final?(%TaskStatusUpdateEvent{}), do: false
  def final?(%TaskArtifactUpdateEvent{}), do: false

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
