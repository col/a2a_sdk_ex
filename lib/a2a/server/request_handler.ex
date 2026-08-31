defmodule A2A.Server.RequestHandler do
  @moduledoc """
  The transport-agnostic RPC surface. Both the JSON-RPC and REST plugs call one
  implementation (`A2A.Server.DefaultHandler`), which implements every callback
  below — `send_message/2` (blocking), `get_task/2`, `send_message_stream/2`,
  `resubscribe/2`, `cancel_task/2`, `list_tasks/2`, and the four push-notification-
  config callbacks (`create_push_config/2`, `get_push_config/2`,
  `list_push_configs/2`, `delete_push_config/2`). The streaming, cancel, list, and
  push-config callbacks are declared as `@optional_callbacks` for the benefit of
  alternate `RequestHandler` implementations that don't need them, not because the
  batteries-included handler skips them — it implements all of them (the push
  callbacks return `:push_notification_not_supported` when the server was not
  started with `push_notifications: true`).
  """
  alias A2A.Types.{
    CancelTaskRequest,
    DeleteTaskPushNotificationConfigRequest,
    GetTaskPushNotificationConfigRequest,
    GetTaskRequest,
    ListTaskPushNotificationConfigsRequest,
    ListTaskPushNotificationConfigsResponse,
    ListTasksRequest,
    ListTasksResponse,
    Message,
    SendMessageRequest,
    SubscribeToTaskRequest,
    Task,
    TaskPushNotificationConfig
  }

  @callback send_message(A2A.Server.t(), SendMessageRequest.t(), keyword()) ::
              {:ok, Task.t() | Message.t()} | {:error, A2A.Error.t()}
  @callback get_task(A2A.Server.t(), GetTaskRequest.t()) ::
              {:ok, Task.t()} | {:error, A2A.Error.t()}
  @callback send_message_stream(A2A.Server.t(), SendMessageRequest.t()) :: Enumerable.t()
  @callback cancel_task(A2A.Server.t(), CancelTaskRequest.t()) ::
              {:ok, Task.t()} | {:error, A2A.Error.t()}
  @callback resubscribe(A2A.Server.t(), SubscribeToTaskRequest.t()) ::
              {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  @callback list_tasks(A2A.Server.t(), ListTasksRequest.t()) ::
              {:ok, ListTasksResponse.t()} | {:error, A2A.Error.t()}
  @callback create_push_config(A2A.Server.t(), TaskPushNotificationConfig.t()) ::
              {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
  @callback get_push_config(A2A.Server.t(), GetTaskPushNotificationConfigRequest.t()) ::
              {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
  @callback list_push_configs(A2A.Server.t(), ListTaskPushNotificationConfigsRequest.t()) ::
              {:ok, ListTaskPushNotificationConfigsResponse.t()} | {:error, A2A.Error.t()}
  @callback delete_push_config(A2A.Server.t(), DeleteTaskPushNotificationConfigRequest.t()) ::
              {:ok, :deleted} | {:error, A2A.Error.t()}

  @optional_callbacks send_message_stream: 2,
                      cancel_task: 2,
                      resubscribe: 2,
                      list_tasks: 2,
                      create_push_config: 2,
                      get_push_config: 2,
                      list_push_configs: 2,
                      delete_push_config: 2
end
