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

    emit(u, evt, false)
  end

  # --- internal ---

  defp status(u, state, message) do
    evt = %TaskStatusUpdateEvent{
      task_id: u.task_id,
      context_id: u.context_id,
      status: %TaskStatus{state: state, message: message}
    }

    # Governs ENDING THE BLOCKING DRAIN (`DefaultHandler.drain/1`). Intentionally
    # ADDS `:input_required` vs `ResultAssembler`'s freeze/terminal set — the
    # drain must stop and return control to the caller when input is required,
    # even though the task itself remains resumable (not frozen).
    emit(u, evt, state in [:completed, :failed, :canceled, :rejected, :input_required])
  end

  defp emit(u, domain_event, terminal?) do
    task = ResultAssembler.apply(u.task, domain_event)
    :ok = u.store.save(task, u.scope)

    :ok =
      Events.broadcast(u.pubsub, %Event{
        task_id: u.task_id,
        context_id: u.context_id,
        payload: domain_event,
        terminal?: terminal?
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
