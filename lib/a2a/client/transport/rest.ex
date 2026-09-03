defmodule A2A.Client.Transport.REST do
  @moduledoc "HTTP+JSON (REST) client transport."
  @behaviour A2A.Client.Transport

  import A2A.Client.Transport, only: [base_headers: 2, http_opts: 3, run: 3]
  alias A2A.Client.Error, as: ClientError

  alias A2A.Client.SSE

  alias A2A.Types.{
    AgentCard,
    ListTaskPushNotificationConfigsResponse,
    ListTasksResponse,
    SendMessageResponse,
    StreamResponse,
    Task,
    TaskPushNotificationConfig
  }

  @impl true
  def send_message(client, request, opts) do
    with {:ok, map} <- post(client, "/message:send", request, opts),
         {:ok, %SendMessageResponse{} = response} <- decode(map, SendMessageResponse) do
      {:ok, response.task || response.message}
    end
  end

  @impl true
  def get_task(client, request, opts) do
    query = drop_nil(%{"historyLength" => request.history_length})
    get(client, "/tasks/" <> request.id, query, Task, opts)
  end

  @impl true
  def cancel_task(client, request, opts) do
    with {:ok, map} <- post_empty(client, "/tasks/" <> request.id <> ":cancel", opts) do
      decode(map, Task)
    end
  end

  @impl true
  def list_tasks(client, request, opts) do
    query =
      drop_nil(%{
        "contextId" => request.context_id,
        "pageSize" => request.page_size,
        "pageToken" => request.page_token,
        "historyLength" => request.history_length
      })

    get(client, "/tasks", query, ListTasksResponse, opts)
  end

  @impl true
  def get_extended_agent_card(client, opts) do
    get(client, "/extendedAgentCard", %{}, AgentCard, opts)
  end

  @impl true
  def create_push_config(client, request, opts) do
    with {:ok, map} <-
           post(client, "/tasks/" <> request.task_id <> "/pushNotificationConfigs", request, opts) do
      decode(map, TaskPushNotificationConfig)
    end
  end

  @impl true
  def get_push_config(client, request, opts) do
    path = "/tasks/" <> request.task_id <> "/pushNotificationConfigs/" <> request.id
    get(client, path, %{}, TaskPushNotificationConfig, opts)
  end

  @impl true
  def list_push_configs(client, request, opts) do
    path = "/tasks/" <> request.task_id <> "/pushNotificationConfigs"
    get(client, path, %{}, ListTaskPushNotificationConfigsResponse, opts)
  end

  @impl true
  def delete_push_config(client, request, opts) do
    path = "/tasks/" <> request.task_id <> "/pushNotificationConfigs/" <> request.id

    request = %{
      method: :delete,
      url: url(client, path, %{}),
      headers: base_headers(client.config, opts),
      body: nil,
      opts: http_opts(client, opts, :unary)
    }

    case run(client, request, :unary) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, ClientError.from_rest(status, body)}
      {:error, %A2A.Error{}} = error -> error
    end
  end

  @impl true
  def send_message_stream(client, request, opts) do
    stream(client, :post, "/message:stream", A2A.JSON.encode!(request), opts)
  end

  @impl true
  def resubscribe(client, request, opts) do
    stream(client, :post, "/tasks/" <> request.id <> ":subscribe", "{}", opts)
  end

  # --- internals ---

  defp stream(client, method, path, body, opts) do
    headers = [{"accept", "text/event-stream"} | base_headers(client.config, opts)]

    request = %{
      method: method,
      url: url(client, path, %{}),
      headers: headers,
      body: body,
      opts: http_opts(client, opts, :stream)
    }

    case run(client, request, :stream) do
      {:ok, %{status: status, body: chunks}} when status in 200..299 -> {:ok, decode_stream(chunks)}
      {:ok, %{status: status, body: body}} -> {:error, ClientError.from_rest(status, collect(body))}
      {:error, %A2A.Error{}} = error -> error
    end
  end

  defp decode_stream(chunks) do
    chunks
    |> SSE.frames()
    |> Stream.map(fn data ->
      {:ok, %StreamResponse{} = stream_response} =
        A2A.JSON.from_json_map(Jason.decode!(data), StreamResponse)

      stream_response.task || stream_response.message || stream_response.status_update ||
        stream_response.artifact_update
    end)
  end

  # A non-2xx streaming response may carry its error body as chunks or binary.
  defp collect(body) when is_binary(body), do: body
  defp collect(chunks), do: chunks |> Enum.to_list() |> IO.iodata_to_binary()

  defp get(client, path, query, module, opts) do
    request = %{
      method: :get,
      url: url(client, path, query),
      headers: base_headers(client.config, opts),
      body: nil,
      opts: http_opts(client, opts, :unary)
    }

    with {:ok, map} <- send_unary(client, request), do: decode(map, module)
  end

  defp post(client, path, request, opts) do
    http_request = %{
      method: :post,
      url: url(client, path, %{}),
      headers: base_headers(client.config, opts),
      body: A2A.JSON.encode!(request),
      opts: http_opts(client, opts, :unary)
    }

    send_unary(client, http_request)
  end

  defp post_empty(client, path, opts) do
    request = %{
      method: :post,
      url: url(client, path, %{}),
      headers: base_headers(client.config, opts),
      body: "{}",
      opts: http_opts(client, opts, :unary)
    }

    send_unary(client, request)
  end

  # Returns {:ok, decoded_json_map} | {:error, A2A.Error.t()}
  defp send_unary(client, request) do
    case run(client, request, :unary) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, Jason.decode!(body)}
      {:ok, %{status: status, body: body}} -> {:error, ClientError.from_rest(status, body)}
      {:error, %A2A.Error{}} = error -> error
    end
  end

  defp decode(map, module) do
    case A2A.JSON.from_json_map(map, module) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        {:error, %A2A.Error{code: :invalid_agent_response, message: inspect(reason)}}
    end
  end

  defp url(%A2A.Client{endpoint: base}, path, query) do
    trimmed = String.trim_trailing(base, "/")
    query_string = if map_size(query) == 0, do: "", else: "?" <> URI.encode_query(query)
    trimmed <> path <> query_string
  end

  defp drop_nil(map) do
    for {key, value} <- map, not is_nil(value), into: %{}, do: {key, to_string(value)}
  end
end
