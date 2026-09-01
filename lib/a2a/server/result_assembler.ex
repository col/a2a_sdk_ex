defmodule A2A.Server.ResultAssembler do
  @moduledoc """
  Folds a stream of domain events into the current `%A2A.Types.Task{}`.
  Used both by `TaskUpdater` (to maintain its projection) and by the handler
  (to assemble the value returned to the caller). Terminal tasks are immutable.
  """
  alias A2A.Types.{Message, Task, TaskArtifactUpdateEvent, TaskStatus, TaskStatusUpdateEvent}

  # Governs task freezing (see `apply/2`) and rejection of new work on a task that
  # has already ended (see `DefaultHandler.resolve_task/2`). These four states are
  # the spec's terminal set (§3.1.2, §3.1.6): the only states that close a stream.
  # `:input_required` and `:auth_required` are INTERRUPTED, not terminal — they end
  # a blocking caller's wait (§3.2.2) but leave the task resumable and the stream
  # open. That rule lives in `DefaultHandler`, not here.
  @terminal_states [:completed, :failed, :canceled, :rejected]

  @doc "Is this `TaskState` one of the four terminal states? The single source of that list."
  @spec terminal_state?(atom()) :: boolean()
  def terminal_state?(state), do: state in @terminal_states

  @spec init(String.t(), String.t() | nil) :: Task.t()
  def init(task_id, context_id),
    do: %Task{id: task_id, context_id: context_id, status: %TaskStatus{state: :submitted}}

  @spec terminal?(Task.t()) :: boolean()
  def terminal?(%Task{status: %TaskStatus{state: s}}), do: terminal_state?(s)
  def terminal?(%Task{}), do: false

  @spec apply(Task.t(), term()) :: Task.t()
  def apply(%Task{} = task, _event) when task.status.state in @terminal_states, do: task

  def apply(%Task{} = task, %TaskStatusUpdateEvent{status: status}) do
    %{task | status: status} |> maybe_append_history(status)
  end

  def apply(%Task{} = task, %TaskArtifactUpdateEvent{artifact: artifact, append: append}) do
    %{task | artifacts: merge_artifact(task.artifacts, artifact, append)}
  end

  def apply(%Task{} = task, %Task{} = snapshot) do
    # start-of-work: adopt id/context/status but keep any assembled history/artifacts
    %{task | id: snapshot.id, context_id: snapshot.context_id, status: snapshot.status}
  end

  def apply(%Task{} = task, %Message{} = msg),
    do: %{task | history: task.history ++ [msg]}

  defp maybe_append_history(task, %TaskStatus{message: nil}), do: task

  defp maybe_append_history(task, %TaskStatus{message: msg}),
    do: %{task | history: task.history ++ [msg]}

  defp merge_artifact(artifacts, %{artifact_id: id} = incoming, append?) do
    case Enum.find_index(artifacts, &(&1.artifact_id == id)) do
      nil ->
        artifacts ++ [incoming]

      idx when append? ->
        List.update_at(artifacts, idx, fn existing ->
          %{existing | parts: existing.parts ++ incoming.parts}
        end)

      idx ->
        List.replace_at(artifacts, idx, incoming)
    end
  end
end
