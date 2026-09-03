defmodule A2A.Client do
  @moduledoc """
  A2A client. Build one with `connect/2`, then call the operation functions.
  The struct is a plain value — hold it, pass it, discard it; it starts no
  process. See `docs/superpowers/specs/2026-09-01-a2a-client-design.md`.
  """
  @type t :: %__MODULE__{
          agent_card: A2A.Types.AgentCard.t(),
          transport: module(),
          endpoint: String.t(),
          config: A2A.Client.Config.t()
        }
  defstruct [:agent_card, :transport, :endpoint, :config]

  alias A2A.Client.{CardResolver, Config, Transport.Selector}

  alias A2A.Types.{
    AgentCard,
    CancelTaskRequest,
    DeleteTaskPushNotificationConfigRequest,
    GetTaskPushNotificationConfigRequest,
    GetTaskRequest,
    ListTaskPushNotificationConfigsRequest,
    ListTasksRequest,
    Message,
    SendMessageRequest,
    SubscribeToTaskRequest,
    TaskPushNotificationConfig
  }

  @spec fetch_agent_card(String.t(), keyword()) ::
          {:ok, AgentCard.t()} | {:error, A2A.Error.t()}
  def fetch_agent_card(url, opts \\ []) when is_binary(url) do
    {config_opts, resolve_opts} = Keyword.split(opts, config_keys())
    CardResolver.resolve(url, Config.new(config_opts), resolve_opts)
  end

  @spec connect(String.t() | AgentCard.t(), keyword()) :: {:ok, t()} | {:error, A2A.Error.t()}
  def connect(url_or_card, opts \\ [])

  def connect(%AgentCard{} = card, opts) do
    {config_opts, rest} = Keyword.split(opts, config_keys())
    config = Config.new(config_opts)
    preferred = pinned(rest) ++ config.preferred_transports

    with {:ok, {module, endpoint}} <- Selector.select(card, preferred) do
      {:ok, %__MODULE__{agent_card: card, transport: module, endpoint: endpoint, config: config}}
    end
  end

  def connect(url, opts) when is_binary(url) do
    with {:ok, card} <- fetch_agent_card(url, opts) do
      connect(card, opts)
    end
  end

  defp pinned(opts) do
    case Keyword.get(opts, :transport) do
      nil -> []
      binding -> [binding]
    end
  end

  @spec agent_card(t()) :: AgentCard.t()
  def agent_card(%__MODULE__{agent_card: card}), do: card

  @spec get_extended_agent_card(t(), keyword()) :: {:ok, AgentCard.t()} | {:error, A2A.Error.t()}
  def get_extended_agent_card(%__MODULE__{} = client, opts \\ []) do
    client.transport.get_extended_agent_card(client, opts)
  end

  @spec send_message(t(), Message.t() | SendMessageRequest.t(), keyword()) ::
          {:ok, A2A.Types.Task.t() | Message.t()} | {:error, A2A.Error.t()}
  def send_message(%__MODULE__{} = client, message, opts \\ []) do
    client.transport.send_message(client, to_send_request(message), opts)
  end

  @spec send_message_stream(t(), Message.t() | SendMessageRequest.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  def send_message_stream(%__MODULE__{} = client, message, opts \\ []) do
    client.transport.send_message_stream(client, to_send_request(message), opts)
  end

  @spec get_task(t(), String.t(), keyword()) :: {:ok, A2A.Types.Task.t()} | {:error, A2A.Error.t()}
  def get_task(%__MODULE__{} = client, task_id, opts \\ []) do
    request = %GetTaskRequest{id: task_id, history_length: opts[:history_length]}
    client.transport.get_task(client, request, opts)
  end

  @spec cancel_task(t(), String.t(), keyword()) ::
          {:ok, A2A.Types.Task.t()} | {:error, A2A.Error.t()}
  def cancel_task(%__MODULE__{} = client, task_id, opts \\ []) do
    client.transport.cancel_task(client, %CancelTaskRequest{id: task_id}, opts)
  end

  @spec list_tasks(t(), keyword()) ::
          {:ok, A2A.Types.ListTasksResponse.t()} | {:error, A2A.Error.t()}
  def list_tasks(%__MODULE__{} = client, opts \\ []) do
    request = %ListTasksRequest{
      context_id: opts[:context_id],
      page_size: opts[:page_size],
      page_token: opts[:page_token],
      history_length: opts[:history_length]
    }

    client.transport.list_tasks(client, request, opts)
  end

  @spec resubscribe(t(), String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  def resubscribe(%__MODULE__{} = client, task_id, opts \\ []) do
    client.transport.resubscribe(client, %SubscribeToTaskRequest{id: task_id}, opts)
  end

  @spec create_push_config(t(), TaskPushNotificationConfig.t(), keyword()) ::
          {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
  def create_push_config(%__MODULE__{} = client, %TaskPushNotificationConfig{} = config, opts \\ []) do
    client.transport.create_push_config(client, config, opts)
  end

  @spec get_push_config(t(), String.t(), String.t(), keyword()) ::
          {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
  def get_push_config(%__MODULE__{} = client, task_id, config_id, opts \\ []) do
    request = %GetTaskPushNotificationConfigRequest{task_id: task_id, id: config_id}
    client.transport.get_push_config(client, request, opts)
  end

  @spec list_push_configs(t(), String.t(), keyword()) ::
          {:ok, A2A.Types.ListTaskPushNotificationConfigsResponse.t()} | {:error, A2A.Error.t()}
  def list_push_configs(%__MODULE__{} = client, task_id, opts \\ []) do
    request = %ListTaskPushNotificationConfigsRequest{
      task_id: task_id,
      page_size: opts[:page_size],
      page_token: opts[:page_token]
    }

    client.transport.list_push_configs(client, request, opts)
  end

  @spec delete_push_config(t(), String.t(), String.t(), keyword()) :: :ok | {:error, A2A.Error.t()}
  def delete_push_config(%__MODULE__{} = client, task_id, config_id, opts \\ []) do
    request = %DeleteTaskPushNotificationConfigRequest{task_id: task_id, id: config_id}
    client.transport.delete_push_config(client, request, opts)
  end

  defp to_send_request(%SendMessageRequest{} = request), do: request
  defp to_send_request(%Message{} = message), do: %SendMessageRequest{message: message}

  # Keys that belong to Config; everything else passes through to the resolver/opts.
  defp config_keys do
    [
      :http_client,
      :http_opts,
      :headers,
      :preferred_transports,
      :streaming?,
      :timeout,
      :stream_timeout,
      :protocol_version
    ]
  end
end
