defmodule A2A.Server.TaskUpdater do
  @moduledoc """
  Ergonomic, task-bound event emitter handed to an executor. Each call builds the
  correctly-shaped domain event, advances the projection, persists it, and broadcasts
  an `Events.Event`. Keeps event-shape correctness in one tested place.
  """
  alias A2A.Server.{Events, ResultAssembler}
  alias A2A.Server.Events.Event

  alias A2A.Types.{
    Artifact,
    Message,
    Part,
    TaskArtifactUpdateEvent,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  @type t :: %__MODULE__{
          task_id: String.t(),
          context_id: String.t(),
          pubsub: atom(),
          store: module(),
          scope: A2A.Scope.t(),
          task: A2A.Types.Task.t()
        }
  defstruct [:task_id, :context_id, :pubsub, :store, :scope, :task]

  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(task_id, context_id, opts) do
    %__MODULE__{
      task_id: task_id,
      context_id: context_id,
      pubsub: Keyword.fetch!(opts, :pubsub),
      store: Keyword.fetch!(opts, :store),
      scope: Keyword.get(opts, :scope, A2A.Scope.default()),
      task: Keyword.get(opts, :task) || ResultAssembler.init(task_id, context_id)
    }
  end

  @spec start_work(t()) :: t()
  def start_work(u), do: status(u, :working, nil)

  @spec update_status(t(), atom(), Message.t() | nil) :: t()
  def update_status(u, state, message \\ nil), do: status(u, state, message)

  @spec complete(t(), Part.t() | nil) :: t()
  def complete(u, part \\ nil), do: status(u, :completed, agent_message(u, part))

  @spec fail(t(), String.t()) :: t()
  def fail(u, reason), do: status(u, :failed, agent_message(u, Part.text(reason)))

  @spec reject(t(), String.t() | nil) :: t()
  def reject(u, reason \\ nil),
    do: status(u, :rejected, agent_message(u, reason && Part.text(reason)))

  @spec requires_input(t(), Message.t() | nil) :: t()
  def requires_input(u, message \\ nil), do: status(u, :input_required, message)

  @doc """
  Answers the caller directly with a `Message`, creating no task.

  Spec §3.1.1: a send may return "a direct response message (for simple
  interactions that don't require task tracking)", and §3.1.2 requires the
  streaming form to be "exactly one Message object and then close immediately".
  Nothing is persisted — there is no task to track — so this ends the
  interaction: emitting anything else afterwards has no task to attach to.
  """
  @spec reply(t(), Part.t() | Message.t()) :: t()
  def reply(u, %Part{} = part), do: reply(u, agent_message(u, part))

  def reply(u, %Message{} = message) do
    :ok =
      Events.broadcast(u.pubsub, %Event{
        task_id: u.task_id,
        context_id: u.context_id,
        payload: message
      })

    u
  end

  @spec add_artifact(t(), Part.t() | Artifact.t(), keyword()) :: t()
  def add_artifact(u, part_or_artifact, opts \\ [])

  def add_artifact(u, %Part{} = part, opts),
    do:
      add_artifact(
        u,
        %Artifact{artifact_id: Keyword.get(opts, :artifact_id, gen_id()), parts: [part]},
        opts
      )

  def add_artifact(u, %Artifact{} = artifact, opts) do
    evt = %TaskArtifactUpdateEvent{
      task_id: u.task_id,
      context_id: u.context_id,
      artifact: artifact,
      append: Keyword.get(opts, :append, false),
      last_chunk: Keyword.get(opts, :last_chunk, true)
    }

    emit(u, evt)
  end

  # --- internal ---

  defp status(u, state, message) do
    evt = %TaskStatusUpdateEvent{
      task_id: u.task_id,
      context_id: u.context_id,
      status: %TaskStatus{
        state: state,
        message: message,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    }

    emit(u, evt)
  end

  defp emit(u, domain_event) do
    task = ResultAssembler.apply(u.task, domain_event)
    :ok = u.store.save(task, u.scope)

    :ok =
      Events.broadcast(u.pubsub, %Event{
        task_id: u.task_id,
        context_id: u.context_id,
        payload: domain_event
      })

    %{u | task: task}
  end

  defp agent_message(_u, nil), do: nil

  defp agent_message(u, %Part{} = part),
    do: %Message{
      message_id: gen_id(),
      role: :agent,
      task_id: u.task_id,
      context_id: u.context_id,
      parts: [part]
    }

  defp gen_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
