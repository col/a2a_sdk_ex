defmodule A2A.Plug.JSONRPC do
  @moduledoc """
  JSON-RPC 2.0 envelope handling and method dispatch for the A2A transport.
  Transport-mechanics only: it decodes the envelope, decodes `params` into the
  typed request via `A2A.JSON`, calls `A2A.Server.DefaultHandler`, and tags the
  result for the router to render. No `Plug.Conn`, no sockets.
  """
  alias A2A.Server.DefaultHandler

  alias A2A.Types.{
    CancelTaskRequest,
    DeleteTaskPushNotificationConfigRequest,
    GetTaskPushNotificationConfigRequest,
    GetTaskRequest,
    ListTaskPushNotificationConfigsRequest,
    ListTasksRequest,
    SendMessageRequest,
    SendMessageResponse,
    SubscribeToTaskRequest,
    TaskPushNotificationConfig
  }

  alias A2A.Types.Task

  @type envelope :: %{method: binary(), params: map(), id: term()}

  # method => {request module, handler kind}
  @methods %{
    "message/send" => {SendMessageRequest, :unary},
    "message/stream" => {SendMessageRequest, :stream},
    "tasks/get" => {GetTaskRequest, :unary},
    "tasks/resubscribe" => {SubscribeToTaskRequest, :stream},
    "tasks/cancel" => {CancelTaskRequest, :unary},
    "tasks/list" => {ListTasksRequest, :unary},
    "tasks/pushNotificationConfig/set" => {TaskPushNotificationConfig, :unary},
    "tasks/pushNotificationConfig/get" => {GetTaskPushNotificationConfigRequest, :unary},
    "tasks/pushNotificationConfig/list" => {ListTaskPushNotificationConfigsRequest, :unary},
    "tasks/pushNotificationConfig/delete" => {DeleteTaskPushNotificationConfigRequest, :unary}
  }

  @spec decode_envelope(binary()) :: {:ok, envelope()} | {:error, map()}
  def decode_envelope(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"jsonrpc" => "2.0", "method" => m} = obj} when is_binary(m) ->
        {:ok, %{method: m, params: Map.get(obj, "params", %{}), id: Map.get(obj, "id")}}

      {:ok, _other} ->
        {:error, error_envelope(nil, -32_600, "invalid request")}

      {:error, _} ->
        {:error, error_envelope(nil, -32_700, "parse error")}
    end
  end

  @spec dispatch(A2A.Server.t(), envelope()) ::
          {:reply, map()} | {:error, map()} | {:stream, term(), Enumerable.t()}
  def dispatch(server, %{method: method, params: params, id: id}) do
    case Map.fetch(@methods, method) do
      {:ok, {mod, kind}} -> decode_and_call(server, id, mod, kind, params)
      :error -> {:error, error_envelope(id, -32_601, "method not found: #{method}")}
    end
  end

  defp decode_and_call(server, id, mod, kind, params) when is_map(params) do
    case A2A.JSON.from_json_map(params, mod) do
      {:ok, req} ->
        call(server, id, kind, req)

      {:error, reason} ->
        {:error, error_envelope(id, -32_602, "invalid params: #{inspect(reason)}")}
    end
  end

  defp decode_and_call(_server, id, _mod, _kind, _params),
    do: {:error, error_envelope(id, -32_602, "invalid params: expected an object")}

  # --- unary ---
  defp call(server, id, :unary, %SendMessageRequest{} = req) do
    case DefaultHandler.send_message(server, req) do
      {:ok, %Task{} = t} -> {:reply, result_envelope(id, SendMessageResponse.task(t))}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  defp call(server, id, :unary, %GetTaskRequest{} = req) do
    case DefaultHandler.get_task(server, req) do
      {:ok, %Task{} = t} -> {:reply, result_envelope(id, t)}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  defp call(server, id, :unary, %CancelTaskRequest{} = req) do
    case DefaultHandler.cancel_task(server, req) do
      {:ok, %Task{} = t} -> {:reply, result_envelope(id, t)}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  defp call(server, id, :unary, %ListTasksRequest{} = req) do
    case DefaultHandler.list_tasks(server, req) do
      {:ok, resp} -> {:reply, result_envelope(id, resp)}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  defp call(server, id, :unary, %TaskPushNotificationConfig{} = req) do
    case DefaultHandler.create_push_config(server, req) do
      {:ok, cfg} -> {:reply, result_envelope(id, cfg)}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  defp call(server, id, :unary, %GetTaskPushNotificationConfigRequest{} = req) do
    case DefaultHandler.get_push_config(server, req) do
      {:ok, cfg} -> {:reply, result_envelope(id, cfg)}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  defp call(server, id, :unary, %ListTaskPushNotificationConfigsRequest{} = req) do
    case DefaultHandler.list_push_configs(server, req) do
      {:ok, resp} -> {:reply, result_envelope(id, resp)}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  defp call(server, id, :unary, %DeleteTaskPushNotificationConfigRequest{} = req) do
    case DefaultHandler.delete_push_config(server, req) do
      {:ok, :deleted} -> {:reply, %{"jsonrpc" => "2.0", "id" => id, "result" => nil}}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  # --- stream ---
  defp call(server, id, :stream, %SendMessageRequest{} = req) do
    case DefaultHandler.send_message_stream(server, req) do
      {:error, err} -> {:error, error_from(id, err)}
      enum -> {:stream, id, enum}
    end
  end

  defp call(server, id, :stream, %SubscribeToTaskRequest{} = req) do
    case DefaultHandler.resubscribe(server, req) do
      {:ok, enum} -> {:stream, id, enum}
      {:error, err} -> {:error, error_from(id, err)}
    end
  end

  @doc "The JSON-RPC response envelope (as iodata) for one streamed event."
  @spec stream_frame(term(), A2A.Types.StreamResponse.t()) :: iodata()
  def stream_frame(id, %A2A.Types.StreamResponse{} = frame),
    do: Jason.encode_to_iodata!(result_envelope(id, frame))

  defp result_envelope(id, struct),
    do: %{"jsonrpc" => "2.0", "id" => id, "result" => A2A.JSON.to_json_map(struct)}

  defp error_from(id, %A2A.Error{} = err),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => A2A.Error.to_jsonrpc(err)}

  defp error_envelope(id, code, message),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
end
