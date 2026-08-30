defmodule A2A.Server.RequestHandler do
  @moduledoc """
  The transport-agnostic RPC surface. Both the (later) JSON-RPC and REST plugs will
  call one implementation. Phase 1 implements `send_message/2` (blocking) and `get_task/2`;
  the streaming, cancel, and listing callbacks are declared but optional.
  """
  alias A2A.Types.{
    GetTaskRequest,
    ListTasksRequest,
    ListTasksResponse,
    Message,
    SendMessageRequest,
    SubscribeToTaskRequest,
    Task
  }

  @callback send_message(A2A.Server.t(), SendMessageRequest.t(), keyword()) ::
              {:ok, Task.t() | Message.t()} | {:error, A2A.Error.t()}
  @callback get_task(A2A.Server.t(), GetTaskRequest.t()) ::
              {:ok, Task.t()} | {:error, A2A.Error.t()}
  @callback send_message_stream(A2A.Server.t(), SendMessageRequest.t()) :: Enumerable.t()
  @callback cancel_task(A2A.Server.t(), term()) :: {:ok, Task.t()} | {:error, A2A.Error.t()}
  @callback resubscribe(A2A.Server.t(), SubscribeToTaskRequest.t()) ::
              {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  @callback list_tasks(A2A.Server.t(), ListTasksRequest.t()) ::
              {:ok, ListTasksResponse.t()} | {:error, A2A.Error.t()}

  @optional_callbacks send_message_stream: 2, cancel_task: 2, resubscribe: 2, list_tasks: 2
end
