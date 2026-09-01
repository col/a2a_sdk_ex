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

    with {:ok, {mod, endpoint}} <- Selector.select(card, preferred) do
      {:ok, %__MODULE__{agent_card: card, transport: mod, endpoint: endpoint, config: config}}
    end
  end

  def connect(url, opts) when is_binary(url) do
    with {:ok, card} <- fetch_agent_card(url, opts), do: connect(card, opts)
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
  def get_extended_agent_card(%__MODULE__{} = c, opts \\ []),
    do: c.transport.get_extended_agent_card(c, opts)

  @spec send_message(t(), Message.t() | SendMessageRequest.t(), keyword()) ::
          {:ok, A2A.Types.Task.t() | Message.t()} | {:error, A2A.Error.t()}
  def send_message(%__MODULE__{} = c, message, opts \\ []),
    do: c.transport.send_message(c, to_send_request(message), opts)

  @spec send_message_stream(t(), Message.t() | SendMessageRequest.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  def send_message_stream(%__MODULE__{} = c, message, opts \\ []),
    do: c.transport.send_message_stream(c, to_send_request(message), opts)

  @spec get_task(t(), String.t(), keyword()) :: {:ok, A2A.Types.Task.t()} | {:error, A2A.Error.t()}
  def get_task(%__MODULE__{} = c, task_id, opts \\ []),
    do:
      c.transport.get_task(
        c,
        %GetTaskRequest{id: task_id, history_length: opts[:history_length]},
        opts
      )

  @spec cancel_task(t(), String.t(), keyword()) ::
          {:ok, A2A.Types.Task.t()} | {:error, A2A.Error.t()}
  def cancel_task(%__MODULE__{} = c, task_id, opts \\ []),
    do: c.transport.cancel_task(c, %CancelTaskRequest{id: task_id}, opts)

  @spec list_tasks(t(), keyword()) ::
          {:ok, A2A.Types.ListTasksResponse.t()} | {:error, A2A.Error.t()}
  def list_tasks(%__MODULE__{} = c, opts \\ []),
    do:
      c.transport.list_tasks(
        c,
        %ListTasksRequest{
          context_id: opts[:context_id],
          page_size: opts[:page_size],
          page_token: opts[:page_token],
          history_length: opts[:history_length]
        },
        opts
      )

  @spec resubscribe(t(), String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  def resubscribe(%__MODULE__{} = c, task_id, opts \\ []),
    do: c.transport.resubscribe(c, %SubscribeToTaskRequest{id: task_id}, opts)

  @spec create_push_config(t(), TaskPushNotificationConfig.t(), keyword()) ::
          {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
  def create_push_config(%__MODULE__{} = c, %TaskPushNotificationConfig{} = cfg, opts \\ []),
    do: c.transport.create_push_config(c, cfg, opts)

  @spec get_push_config(t(), String.t(), String.t(), keyword()) ::
          {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
  def get_push_config(%__MODULE__{} = c, task_id, config_id, opts \\ []),
    do:
      c.transport.get_push_config(
        c,
        %GetTaskPushNotificationConfigRequest{task_id: task_id, id: config_id},
        opts
      )

  @spec list_push_configs(t(), String.t(), keyword()) ::
          {:ok, A2A.Types.ListTaskPushNotificationConfigsResponse.t()} | {:error, A2A.Error.t()}
  def list_push_configs(%__MODULE__{} = c, task_id, opts \\ []),
    do:
      c.transport.list_push_configs(
        c,
        %ListTaskPushNotificationConfigsRequest{
          task_id: task_id,
          page_size: opts[:page_size],
          page_token: opts[:page_token]
        },
        opts
      )

  @spec delete_push_config(t(), String.t(), String.t(), keyword()) :: :ok | {:error, A2A.Error.t()}
  def delete_push_config(%__MODULE__{} = c, task_id, config_id, opts \\ []),
    do:
      c.transport.delete_push_config(
        c,
        %DeleteTaskPushNotificationConfigRequest{task_id: task_id, id: config_id},
        opts
      )

  defp to_send_request(%SendMessageRequest{} = r), do: r
  defp to_send_request(%Message{} = m), do: %SendMessageRequest{message: m}

  # Keys that belong to Config; everything else passes through to the resolver/opts.
  defp config_keys,
    do: [
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
