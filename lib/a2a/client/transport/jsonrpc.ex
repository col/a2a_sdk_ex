defmodule A2A.Client.Transport.JSONRPC do
  @moduledoc "JSON-RPC 2.0 client transport."
  @behaviour A2A.Client.Transport

  import A2A.Client.Transport, only: [base_headers: 2, http_opts: 3, run: 3]
  alias A2A.Client.Error, as: ClientError
  alias A2A.Client.SSE

  alias A2A.Types.{
    AgentCard,
    GetExtendedAgentCardRequest,
    ListTaskPushNotificationConfigsResponse,
    ListTasksResponse,
    SendMessageResponse,
    StreamResponse,
    Task,
    TaskPushNotificationConfig
  }

  @impl true
  def send_message(client, request, opts) do
    with {:ok, result} <- call(client, "SendMessage", request, opts),
         {:ok, %SendMessageResponse{} = response} <-
           to_result(A2A.JSON.from_json_map(result, SendMessageResponse)) do
      {:ok, response.task || response.message}
    end
  end

  @impl true
  def get_task(client, request, opts), do: unary(client, "GetTask", request, Task, opts)

  @impl true
  def cancel_task(client, request, opts), do: unary(client, "CancelTask", request, Task, opts)

  @impl true
  def list_tasks(client, request, opts) do
    unary(client, "ListTasks", request, ListTasksResponse, opts)
  end

  @impl true
  def get_extended_agent_card(client, opts) do
    unary(client, "GetExtendedAgentCard", %GetExtendedAgentCardRequest{}, AgentCard, opts)
  end

  @impl true
  def create_push_config(client, request, opts) do
    unary(client, "CreateTaskPushNotificationConfig", request, TaskPushNotificationConfig, opts)
  end

  @impl true
  def get_push_config(client, request, opts) do
    unary(client, "GetTaskPushNotificationConfig", request, TaskPushNotificationConfig, opts)
  end

  @impl true
  def list_push_configs(client, request, opts) do
    unary(
      client,
      "ListTaskPushNotificationConfigs",
      request,
      ListTaskPushNotificationConfigsResponse,
      opts
    )
  end

  @impl true
  def delete_push_config(client, request, opts) do
    with {:ok, _result} <- call(client, "DeleteTaskPushNotificationConfig", request, opts) do
      :ok
    end
  end

  @impl true
  def send_message_stream(client, request, opts) do
    stream(client, "SendStreamingMessage", request, opts)
  end

  @impl true
  def resubscribe(client, request, opts) do
    stream(client, "SubscribeToTask", request, opts)
  end

  # --- internals ---

  defp stream(client, method, request, opts) do
    id = System.unique_integer([:positive])

    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => A2A.JSON.to_json_map(request)
      })

    headers = [{"accept", "text/event-stream"} | base_headers(client.config, opts)]

    request = %{
      method: :post,
      url: client.endpoint,
      headers: headers,
      body: body,
      opts: http_opts(client, opts, :stream)
    }

    with {:ok, response} <- run(client, request, :stream) do
      handle_stream_response(response)
    end
  end

  # A pre-stream rejection replies HTTP 200 with `content-type: application/json`
  # carrying a JSON-RPC error envelope instead of an SSE body — detect that by
  # content-type (not status, which JSON-RPC always answers 200) and surface the
  # decoded `A2A.Error` instead of silently handing SSE.frames an empty stream.
  defp handle_stream_response(%{headers: headers, body: body}) do
    if event_stream?(headers) do
      {:ok, decode_stream(body)}
    else
      decode_non_stream_body(body)
    end
  end

  defp event_stream?(headers) do
    Enum.any?(headers, fn {k, v} ->
      String.downcase(k) == "content-type" and
        String.contains?(String.downcase(v), "text/event-stream")
    end)
  end

  defp decode_non_stream_body(body) do
    case Jason.decode(collect(body)) do
      {:ok, %{"error" => error}} -> {:error, ClientError.from_jsonrpc(error)}
      _ -> {:error, %A2A.Error{code: :invalid_agent_response, message: "expected SSE stream"}}
    end
  end

  # The error body may arrive as a binary or as an enumerable of chunks.
  defp collect(body) when is_binary(body), do: body
  defp collect(chunks), do: chunks |> Enum.to_list() |> IO.iodata_to_binary()

  # chunks :: Enumerable of raw binary body parts
  defp decode_stream(chunks) do
    chunks
    |> SSE.frames()
    |> Stream.map(&decode_frame/1)
  end

  # Each JSON-RPC SSE frame is a full envelope carrying one StreamResponse in result.
  defp decode_frame(data) do
    case Jason.decode!(data) do
      %{"result" => result} ->
        {:ok, %StreamResponse{} = stream_response} =
          A2A.JSON.from_json_map(result, StreamResponse)

        stream_response.task || stream_response.message || stream_response.status_update ||
          stream_response.artifact_update

      %{"error" => error} ->
        raise ClientError.from_jsonrpc(error)
    end
  end

  defp unary(client, method, request, result_module, opts) do
    with {:ok, result} <- call(client, method, request, opts) do
      to_result(A2A.JSON.from_json_map(result, result_module))
    end
  end

  defp to_result({:ok, value}), do: {:ok, value}

  defp to_result({:error, reason}) do
    {:error, %A2A.Error{code: :invalid_agent_response, message: inspect(reason)}}
  end

  # Returns {:ok, result_map} | {:error, A2A.Error.t()}
  defp call(client, method, request, opts) do
    id = System.unique_integer([:positive])

    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => A2A.JSON.to_json_map(request)
      })

    request = %{
      method: :post,
      url: client.endpoint,
      headers: base_headers(client.config, opts),
      body: body,
      opts: http_opts(client, opts, :unary)
    }

    with {:ok, %{body: raw_body}} <- run(client, request, :unary) do
      decode_envelope(raw_body)
    end
  end

  defp decode_envelope(raw_body) do
    case Jason.decode(raw_body) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:ok, %{"error" => error}} -> {:error, ClientError.from_jsonrpc(error)}
      {:ok, _} -> {:error, %A2A.Error{code: :invalid_agent_response, message: "no result or error"}}
      {:error, _} -> {:error, %A2A.Error{code: :invalid_agent_response, message: "invalid JSON"}}
    end
  end
end
