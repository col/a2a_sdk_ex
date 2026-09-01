defmodule A2A.Client.Transport do
  @moduledoc "Behaviour + shared helpers for client transports (JSON-RPC, REST)."
  alias A2A.Types.{
    AgentCard,
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

  @type client :: A2A.Client.t()
  @type opts :: keyword()

  @callback send_message(client, SendMessageRequest.t(), opts) ::
              {:ok, Task.t() | Message.t()} | {:error, A2A.Error.t()}
  @callback send_message_stream(client, SendMessageRequest.t(), opts) ::
              {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  @callback get_task(client, GetTaskRequest.t(), opts) :: {:ok, Task.t()} | {:error, A2A.Error.t()}
  @callback cancel_task(client, CancelTaskRequest.t(), opts) ::
              {:ok, Task.t()} | {:error, A2A.Error.t()}
  @callback list_tasks(client, ListTasksRequest.t(), opts) ::
              {:ok, ListTasksResponse.t()} | {:error, A2A.Error.t()}
  @callback resubscribe(client, SubscribeToTaskRequest.t(), opts) ::
              {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  @callback get_extended_agent_card(client, opts) :: {:ok, AgentCard.t()} | {:error, A2A.Error.t()}
  @callback create_push_config(client, TaskPushNotificationConfig.t(), opts) ::
              {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
  @callback get_push_config(client, GetTaskPushNotificationConfigRequest.t(), opts) ::
              {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
  @callback list_push_configs(client, ListTaskPushNotificationConfigsRequest.t(), opts) ::
              {:ok, ListTaskPushNotificationConfigsResponse.t()} | {:error, A2A.Error.t()}
  @callback delete_push_config(client, DeleteTaskPushNotificationConfigRequest.t(), opts) ::
              :ok | {:error, A2A.Error.t()}

  @spec base_headers(A2A.Client.Config.t(), opts) :: [{String.t(), String.t()}]
  def base_headers(%A2A.Client.Config{} = cfg, opts) do
    defaults = [{"content-type", "application/json"}, {"a2a-version", cfg.protocol_version}]
    merge_headers(defaults ++ cfg.headers, Keyword.get(opts, :headers, []))
  end

  # Later (per-call) headers win on case-insensitive key.
  defp merge_headers(base, override) do
    Enum.reduce(override, base, fn {k, v}, acc ->
      [{k, v} | Enum.reject(acc, fn {ek, _} -> String.downcase(ek) == String.downcase(k) end)]
    end)
  end

  @spec http_opts(client, opts, :unary | :stream) :: keyword()
  def http_opts(%A2A.Client{config: cfg}, opts, :unary),
    do: Keyword.merge(cfg.http_opts, timeout: Keyword.get(opts, :timeout, cfg.timeout))

  def http_opts(%A2A.Client{config: cfg}, opts, :stream),
    do:
      Keyword.merge(cfg.http_opts,
        stream_timeout: Keyword.get(opts, :stream_timeout, cfg.stream_timeout)
      )

  @spec run(client, A2A.Client.HTTP.request(), :unary | :stream) ::
          {:ok, A2A.Client.HTTP.response()} | {:error, A2A.Error.t()}
  def run(%A2A.Client{config: %{http_client: http}}, req, :unary) do
    wrap(http.request(req))
  end

  def run(%A2A.Client{config: %{http_client: http}}, req, :stream) do
    wrap(http.stream(req))
  end

  defp wrap({:ok, resp}), do: {:ok, resp}
  defp wrap({:error, reason}), do: {:error, A2A.Client.Error.from_transport(reason)}
end
