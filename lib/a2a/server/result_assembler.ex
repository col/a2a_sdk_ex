defmodule A2A.Server.ResultAssembler do
  @moduledoc false
  alias A2A.Types.{Message, Task, TaskArtifactUpdateEvent, TaskStatus, TaskStatusUpdateEvent}

  # Governs task freezing (see `apply/2`) and rejection of new work on a task
  # that has already ended (see `DefaultHandler.reject_terminal/2`). Deliberately
  # EXCLUDES `:input_required` — that state must remain resumable, unlike the
  # `TaskUpdater` terminal set below, which ends the blocking drain on it too.
  @terminal_states [:completed, :failed, :canceled, :rejected]

  @spec init(String.t(), String.t() | nil) :: Task.t()
  def init(task_id, context_id),
    do: %Task{id: task_id, context_id: context_id, status: %TaskStatus{state: :submitted}}

  @spec terminal?(Task.t()) :: boolean()
  def terminal?(%Task{status: %TaskStatus{state: s}}), do: s in @terminal_states
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
