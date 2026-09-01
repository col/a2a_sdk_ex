defmodule A2A.Plug.REST do
  @moduledoc """
  HTTP+JSON/REST binding mechanics: build a typed request from path/query/body,
  call `A2A.Server.DefaultHandler`, and tag the result for the router to render
  (or an error via `A2A.Error.to_rest/1`). Transport mechanics only —
  no `Plug.Conn`, no sockets.
  """
  alias A2A.Server.DefaultHandler

  alias A2A.Types.{
    CancelTaskRequest,
    DeleteTaskPushNotificationConfigRequest,
    GetTaskPushNotificationConfigRequest,
    GetTaskRequest,
    ListTaskPushNotificationConfigsRequest,
    ListTasksRequest,
    Message,
    SendMessageRequest,
    SendMessageResponse,
    SubscribeToTaskRequest,
    Task,
    TaskPushNotificationConfig
  }

  # Spec section 11.1 mandates `application/json` for REST requests and responses.
  # `application/a2a+json` (registered in section 14.1.1, and used by the section 6
  # examples) is deliberately not used here: it is not what the binding section
  # requires, and it fails a client matching on the `application/json` subtype.
  @content_type "application/json"
  @spec content_type() :: String.t()
  def content_type, do: @content_type

  @doc "REST SSE frame formatter: the bare `StreamResponse` ProtoJSON (no envelope)."
  @spec frame(term(), A2A.Types.StreamResponse.t()) :: iodata()
  def frame(_id, %A2A.Types.StreamResponse{} = f),
    do: Jason.encode_to_iodata!(A2A.JSON.to_json_map(f))

  # --- unary ---

  def send_message(server, body) when is_map(body) do
    with {:ok, req} <- decode(body, SendMessageRequest),
         {:ok, result} <- DefaultHandler.send_message(server, req) do
      {:reply, 200, A2A.JSON.to_json_map(send_response(result))}
    else
      {:error, %A2A.Error{} = e} -> render_error(e)
      {:error, reason} -> bad_request(reason)
    end
  end

  # `SendMessageResponse` is a oneof: the agent either created a task or answered
  # directly with a message (spec 3.1.1).
  defp send_response(%Task{} = t), do: SendMessageResponse.task(t)
  defp send_response(%Message{} = m), do: SendMessageResponse.message(m)

  # Spec 11.5: a GET carries its request parameters as camelCase query
  # parameters, so `?historyLength=n` is the REST spelling of the JSON-RPC
  # request field. Both spellings are accepted, as elsewhere in this module.
  def get_task(server, id, query \\ %{}) do
    req = %GetTaskRequest{
      id: id,
      history_length: parse_int(query["historyLength"] || query["history_length"])
    }

    case DefaultHandler.get_task(server, req) do
      {:ok, %Task{} = t} -> {:reply, 200, A2A.JSON.to_json_map(t)}
      {:error, %A2A.Error{} = e} -> render_error(e)
    end
  end

  def list_tasks(server, query) when is_map(query) do
    case DefaultHandler.list_tasks(server, list_request(query)) do
      {:ok, resp} -> {:reply, 200, A2A.JSON.to_json_map(resp)}
      {:error, %A2A.Error{} = e} -> render_error(e)
    end
  end

  def cancel_task(server, id, _body) do
    case DefaultHandler.cancel_task(server, %CancelTaskRequest{id: id}) do
      {:ok, %Task{} = t} -> {:reply, 200, A2A.JSON.to_json_map(t)}
      {:error, %A2A.Error{} = e} -> render_error(e)
    end
  end

  def set_push_config(server, task_id, body) when is_map(body) do
    with {:ok, %TaskPushNotificationConfig{} = cfg} <- decode(body, TaskPushNotificationConfig),
         {:ok, stored} <- DefaultHandler.create_push_config(server, %{cfg | task_id: task_id}) do
      {:reply, 200, A2A.JSON.to_json_map(stored)}
    else
      {:error, %A2A.Error{} = e} -> render_error(e)
      {:error, reason} -> bad_request(reason)
    end
  end

  def get_push_config(server, task_id, id) do
    case DefaultHandler.get_push_config(server, %GetTaskPushNotificationConfigRequest{
           task_id: task_id,
           id: id
         }) do
      {:ok, cfg} -> {:reply, 200, A2A.JSON.to_json_map(cfg)}
      {:error, %A2A.Error{} = e} -> render_error(e)
    end
  end

  def list_push_configs(server, task_id) do
    case DefaultHandler.list_push_configs(server, %ListTaskPushNotificationConfigsRequest{
           task_id: task_id
         }) do
      {:ok, resp} -> {:reply, 200, A2A.JSON.to_json_map(resp)}
      {:error, %A2A.Error{} = e} -> render_error(e)
    end
  end

  def delete_push_config(server, task_id, id) do
    case DefaultHandler.delete_push_config(server, %DeleteTaskPushNotificationConfigRequest{
           task_id: task_id,
           id: id
         }) do
      {:ok, :deleted} -> {:reply, 200, %{}}
      {:error, %A2A.Error{} = e} -> render_error(e)
    end
  end

  # --- streaming ---

  def stream_message(server, body) when is_map(body) do
    case decode(body, SendMessageRequest) do
      {:ok, req} ->
        case DefaultHandler.send_message_stream(server, req) do
          {:error, %A2A.Error{} = e} -> render_error(e)
          enum -> {:stream, enum}
        end

      {:error, %A2A.Error{} = e} ->
        render_error(e)

      {:error, reason} ->
        bad_request(reason)
    end
  end

  def subscribe(server, id) do
    case DefaultHandler.resubscribe(server, %SubscribeToTaskRequest{id: id}) do
      {:ok, enum} -> {:stream, enum}
      {:error, %A2A.Error{} = e} -> render_error(e)
    end
  end

  # --- helpers ---

  defp decode(map, mod) do
    case A2A.JSON.from_json_map(map, mod) do
      {:ok, req} -> {:ok, req}
      {:error, reason} -> {:error, reason}
    end
  end

  # Build a ListTasksRequest from string-keyed query params (values are strings).
  defp list_request(q) do
    %ListTasksRequest{
      context_id: q["context_id"] || q["contextId"],
      status: parse_status(q["status"]),
      page_size: parse_int(q["page_size"] || q["pageSize"]),
      page_token: q["page_token"] || q["pageToken"],
      history_length: parse_int(q["history_length"] || q["historyLength"]),
      status_timestamp_after: parse_ts(q["status_timestamp_after"] || q["statusTimestampAfter"]),
      include_artifacts: parse_bool(q["include_artifacts"] || q["includeArtifacts"])
    }
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_bool("true"), do: true
  defp parse_bool("false"), do: false
  defp parse_bool(_), do: nil

  defp parse_ts(nil), do: nil

  defp parse_ts(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_status(nil), do: nil

  defp parse_status(s) do
    # Reuse the codec's enum decoding for a proto TASK_STATE_* string; if the
    # client sent a bare atom-ish value, try that too.
    case A2A.JSON.from_json_map(%{"status" => s}, ListTasksRequest) do
      {:ok, %ListTasksRequest{status: st}} -> st
      _ -> nil
    end
  end

  defp render_error(%A2A.Error{} = e) do
    {status, body} = A2A.Error.to_rest(e)
    {:error, status, body}
  end

  # A decode failure is an ordinary A2A.Error, so it renders through the same
  # AIP-193 projection as every other error rather than a hand-built body.
  defp bad_request(reason) do
    render_error(%A2A.Error{
      code: :invalid_params,
      message: "invalid request: #{inspect(reason)}"
    })
  end
end
