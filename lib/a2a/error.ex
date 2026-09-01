defmodule A2A.Error do
  @moduledoc """
  A protocol-level error, returned as `{:error, %A2A.Error{}}` from server
  handler functions. `to_jsonrpc/1` renders it as a JSON-RPC 2.0 error object;
  `to_rest/1` renders it as `{http_status, body}` for the REST binding. Also
  raisable/rescuable as an exception (`code`, `message`, `data`).
  """
  @type t :: %__MODULE__{code: atom(), message: String.t(), data: term()}
  defexception code: :internal_error, message: "error", data: nil

  @spec not_found(String.t()) :: t()
  def not_found(task_id),
    do: %__MODULE__{
      code: :task_not_found,
      message: "task not found: #{task_id}",
      data: %{task_id: task_id}
    }

  @spec terminal_task(String.t()) :: t()
  def terminal_task(task_id),
    do: %__MODULE__{
      code: :task_not_continuable,
      message: "task is in a terminal state and cannot be continued: #{task_id}",
      data: %{task_id: task_id}
    }

  @spec not_cancelable(String.t()) :: t()
  def not_cancelable(task_id),
    do: %__MODULE__{
      code: :task_not_cancelable,
      message: "task is not in a cancelable state: #{task_id}",
      data: %{task_id: task_id}
    }

  # One table; to_jsonrpc/1 and to_rest/1 are projections of it.
  # grpc = canonical google.rpc.Code int; reason = A2A ErrorInfo reason (UPPER_SNAKE_CASE).
  @errors %{
    task_not_found: %{jsonrpc: -32_001, http: 404, grpc: 5, reason: "TASK_NOT_FOUND"},
    task_not_cancelable: %{jsonrpc: -32_002, http: 400, grpc: 9, reason: "TASK_NOT_CANCELABLE"},
    task_not_continuable: %{jsonrpc: -32_002, http: 400, grpc: 9, reason: "TASK_NOT_CONTINUABLE"},
    task_in_progress: %{jsonrpc: -32_002, http: 409, grpc: 10, reason: "TASK_IN_PROGRESS"},
    push_notification_not_supported: %{
      jsonrpc: -32_003,
      http: 400,
      grpc: 12,
      reason: "PUSH_NOTIFICATION_NOT_SUPPORTED"
    },
    unsupported_operation: %{jsonrpc: -32_004, http: 400, grpc: 12, reason: "UNSUPPORTED_OPERATION"},
    invalid_params: %{jsonrpc: -32_602, http: 400, grpc: 3, reason: "INVALID_ARGUMENT"},
    content_type_not_supported: %{
      jsonrpc: -32_005,
      http: 400,
      grpc: 3,
      reason: "CONTENT_TYPE_NOT_SUPPORTED"
    },
    invalid_agent_response: %{
      jsonrpc: -32_006,
      http: 500,
      grpc: 13,
      reason: "INVALID_AGENT_RESPONSE"
    },
    timeout: %{jsonrpc: -32_603, http: 504, grpc: 4, reason: "TIMEOUT"},
    internal_error: %{jsonrpc: -32_603, http: 500, grpc: 13, reason: "INTERNAL_ERROR"}
  }

  @doc """
  Renders this semantic error as a JSON-RPC 2.0 error object
  (`%{"code" => integer, "message" => binary, optional "data" => term}`).
  Unmapped/internal codes fall back to `-32603`.
  """
  @spec to_jsonrpc(t()) :: %{required(String.t()) => term()}
  def to_jsonrpc(%__MODULE__{code: code, message: message, data: data}) do
    jsonrpc =
      case Map.get(@errors, code) do
        %{jsonrpc: c} -> c
        _ -> -32_603
      end

    base = %{"code" => jsonrpc, "message" => message}
    if is_nil(data), do: base, else: Map.put(base, "data", data)
  end

  @doc """
  Renders this semantic error for the REST binding as `{http_status, body}` where
  `body` is the ProtoJSON of `google.rpc.Status` carrying a `google.rpc.ErrorInfo`
  detail (`reason` UPPER_SNAKE_CASE, `domain` `"a2a-protocol.org"`, `metadata` from
  `data`). Unmapped/internal codes fall back to `500` / `INTERNAL`.
  """
  @spec to_rest(t()) :: {pos_integer(), %{required(String.t()) => term()}}
  def to_rest(%__MODULE__{code: code, message: message, data: data}) do
    e = Map.get(@errors, code, @errors.internal_error)

    detail =
      %{
        "@type" => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason" => e.reason,
        "domain" => "a2a-protocol.org"
      }
      |> maybe_put_metadata(data)

    {e.http, %{"code" => e.grpc, "message" => message, "details" => [detail]}}
  end

  defp maybe_put_metadata(detail, nil), do: detail

  defp maybe_put_metadata(detail, data) when is_map(data),
    do: Map.put(detail, "metadata", Map.new(data, fn {k, v} -> {to_string(k), to_string(v)} end))
end
