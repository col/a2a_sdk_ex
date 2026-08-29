defmodule A2A.Test.Fixtures do
  @moduledoc """
  One hand-built, non-trivial instance per covered `A2A.Types.*` message.
  Reused by the golden-file tests and by the Tier 2 differential-oracle
  conformance test (`test/a2a/proto_conformance_test.exs`) so both suites
  exercise exactly the same representative data.
  """

  alias A2A.Types.{
    Artifact,
    GetTaskRequest,
    Message,
    Part,
    SendMessageConfiguration,
    SendMessageRequest,
    SendMessageResponse,
    StreamResponse,
    Task,
    TaskArtifactUpdateEvent,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  @doc "Returns `[{module, struct}, ...]`, one instance per covered message."
  @spec all() :: [{module, struct}]
  def all do
    [
      {Message, message()},
      {Part, part()},
      {Artifact, artifact()},
      {TaskStatus, task_status()},
      {Task, task()},
      {TaskStatusUpdateEvent, task_status_update_event()},
      {TaskArtifactUpdateEvent, task_artifact_update_event()},
      {StreamResponse, stream_response()},
      {SendMessageConfiguration, send_message_configuration()},
      {SendMessageRequest, send_message_request()},
      {SendMessageResponse, send_message_response()},
      {GetTaskRequest, get_task_request()}
    ]
  end

  def message do
    %Message{
      message_id: "msg-1",
      context_id: "ctx-1",
      task_id: "task-1",
      role: :user,
      parts: [Part.text("hello"), Part.data(%{"n" => 1})],
      metadata: %{"origin" => "test"},
      extensions: ["ext-a"],
      reference_task_ids: ["task-0"]
    }
  end

  def part,
    do: Part.url("https://example.com/file.png", filename: "file.png", media_type: "image/png")

  def artifact do
    %Artifact{
      artifact_id: "art-1",
      name: "result",
      description: "the result artifact",
      parts: [Part.text("done")],
      metadata: %{"score" => 1},
      extensions: ["ext-b"]
    }
  end

  def task_status do
    %TaskStatus{
      state: :completed,
      message: %Message{message_id: "msg-2", role: :agent, parts: [Part.text("ok")]},
      timestamp: DateTime.from_unix!(1_700_000_000)
    }
  end

  def task do
    %Task{
      id: "task-1",
      context_id: "ctx-1",
      status: task_status(),
      artifacts: [artifact()],
      history: [message()],
      metadata: %{"k" => true}
    }
  end

  def task_status_update_event do
    %TaskStatusUpdateEvent{
      task_id: "task-1",
      context_id: "ctx-1",
      status: task_status(),
      metadata: %{"final" => false}
    }
  end

  def task_artifact_update_event do
    %TaskArtifactUpdateEvent{
      task_id: "task-1",
      context_id: "ctx-1",
      artifact: artifact(),
      append: true,
      last_chunk: false,
      metadata: %{"seq" => 2}
    }
  end

  def stream_response, do: StreamResponse.status_update(task_status_update_event())

  def send_message_configuration do
    %SendMessageConfiguration{
      accepted_output_modes: ["text/plain"],
      history_length: 5,
      return_immediately: true
    }
  end

  def send_message_request do
    %SendMessageRequest{
      tenant: "tenant-1",
      message: message(),
      configuration: send_message_configuration(),
      metadata: %{"trace" => "abc"}
    }
  end

  def send_message_response, do: SendMessageResponse.task(task())

  def get_task_request, do: %GetTaskRequest{tenant: "tenant-1", id: "task-1", history_length: 10}
end
