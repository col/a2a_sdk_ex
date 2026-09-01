defmodule A2A.Server.StreamFrame do
  @moduledoc false
  alias A2A.Types.{Message, StreamResponse, Task, TaskArtifactUpdateEvent, TaskStatusUpdateEvent}

  @spec of(Task.t() | Message.t() | TaskStatusUpdateEvent.t() | TaskArtifactUpdateEvent.t()) ::
          StreamResponse.t()
  def of(%Task{} = t), do: StreamResponse.task(t)
  def of(%Message{} = m), do: StreamResponse.message(m)
  def of(%TaskStatusUpdateEvent{} = e), do: StreamResponse.status_update(e)
  def of(%TaskArtifactUpdateEvent{} = e), do: StreamResponse.artifact_update(e)
end
