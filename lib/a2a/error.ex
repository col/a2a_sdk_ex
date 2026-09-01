defmodule A2A.Error do
  @moduledoc """
  A protocol-level error, returned as `{:error, %A2A.Error{}}` from server
  handler functions. `to_jsonrpc/1` renders it as a JSON-RPC 2.0 error object;
  `to_rest/1` renders it as `{http_status, body}` for the REST binding. Also
  raisable/rescuable as an exception (`code`, `message`, `data`).
  """
  alias A2A.JSON.Naming

  @type t :: %__MODULE__{code: atom(), message: String.t(), data: term()}
  defexception code: :internal_error, message: "error", data: nil

  @error_info_type "type.googleapis.com/google.rpc.ErrorInfo"
  @domain "a2a-protocol.org"

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

  # One table; to_jsonrpc/1 and to_rest/1 are projections of it. Codes, statuses
  # and gRPC status names are the spec §5.4 mapping verbatim. `reason` is the
  # ErrorInfo reason (UPPER_SNAKE_CASE, no "Error" suffix) and is `nil` for the
  # standard JSON-RPC errors, which the spec gives no A2A reason.
  @unsupported %{
    jsonrpc: -32_004,
    http: 400,
    grpc: "UNIMPLEMENTED",
    reason: "UNSUPPORTED_OPERATION"
  }

  @errors %{
    task_not_found: %{jsonrpc: -32_001, http: 404, grpc: "NOT_FOUND", reason: "TASK_NOT_FOUND"},
    task_not_cancelable: %{
      jsonrpc: -32_002,
      http: 409,
      grpc: "FAILED_PRECONDITION",
      reason: "TASK_NOT_CANCELABLE"
    },
    push_notification_not_supported: %{
      jsonrpc: -32_003,
      http: 400,
      grpc: "UNIMPLEMENTED",
      reason: "PUSH_NOTIFICATION_NOT_SUPPORTED"
    },
    unsupported_operation: @unsupported,
    # §3.4 and §3.6: a message sent to, or a subscribe on, a task in a terminal
    # state is UnsupportedOperationError — as is asking this SDK to accept a
    # second message while the first is still executing.
    task_not_continuable: @unsupported,
    task_in_progress: @unsupported,
    content_type_not_supported: %{
      jsonrpc: -32_005,
      http: 415,
      grpc: "INVALID_ARGUMENT",
      reason: "CONTENT_TYPE_NOT_SUPPORTED"
    },
    invalid_agent_response: %{
      jsonrpc: -32_006,
      http: 502,
      grpc: "INTERNAL",
      reason: "INVALID_AGENT_RESPONSE"
    },
    extended_agent_card_not_configured: %{
      jsonrpc: -32_007,
      http: 400,
      grpc: "FAILED_PRECONDITION",
      reason: "EXTENDED_AGENT_CARD_NOT_CONFIGURED"
    },
    extension_support_required: %{
      jsonrpc: -32_008,
      http: 400,
      grpc: "FAILED_PRECONDITION",
      reason: "EXTENSION_SUPPORT_REQUIRED"
    },
    version_not_supported: %{
      jsonrpc: -32_009,
      http: 400,
      grpc: "UNIMPLEMENTED",
      reason: "VERSION_NOT_SUPPORTED"
    },
    method_not_found: %{jsonrpc: -32_601, http: 404, grpc: "NOT_FOUND", reason: nil},
    invalid_params: %{jsonrpc: -32_602, http: 400, grpc: "INVALID_ARGUMENT", reason: nil},
    timeout: %{jsonrpc: -32_603, http: 504, grpc: "DEADLINE_EXCEEDED", reason: nil},
    internal_error: %{jsonrpc: -32_603, http: 500, grpc: "INTERNAL", reason: nil}
  }

  @doc """
  Renders this semantic error as a JSON-RPC 2.0 error object
  (`%{"code" => integer, "message" => binary, optional "data" => term}`).

  For A2A-specific errors `data` is the §9.5 array holding a `google.rpc.ErrorInfo`;
  for standard errors it is the error's own `data`, omitted when `nil`. Unmapped
  codes fall back to `-32603`.
  """
  @spec to_jsonrpc(t()) :: %{required(String.t()) => term()}
  def to_jsonrpc(%__MODULE__{code: code, message: message, data: data}) do
    e = mapping(code)
    base = %{"code" => e.jsonrpc, "message" => message}

    case error_info(e, data) do
      nil -> if is_nil(data), do: base, else: Map.put(base, "data", data)
      info -> Map.put(base, "data", [info])
    end
  end

  @doc """
  Renders this semantic error for the REST binding as `{http_status, body}`, where
  `body` is the AIP-193 representation the spec mandates in §11.6: an `error`
  object whose `code` is the HTTP status, `status` the gRPC status name, and
  `details` an array carrying a `google.rpc.ErrorInfo` for A2A-specific errors.
  Unmapped codes fall back to `500` / `INTERNAL`.
  """
  @spec to_rest(t()) :: {pos_integer(), %{required(String.t()) => term()}}
  def to_rest(%__MODULE__{code: code, message: message, data: data}) do
    e = mapping(code)

    error =
      %{"code" => e.http, "status" => e.grpc, "message" => message}
      |> maybe_put("details", List.wrap(error_info(e, data)))

    {e.http, %{"error" => error}}
  end

  defp mapping(code), do: Map.get(@errors, code, @errors.internal_error)

  # Only A2A-specific errors have a reason, and so an ErrorInfo.
  defp error_info(%{reason: nil}, _data), do: nil

  defp error_info(%{reason: reason}, data) do
    %{"@type" => @error_info_type, "reason" => reason, "domain" => @domain}
    |> maybe_put("metadata", metadata(data))
  end

  # ErrorInfo metadata is a string map; keys follow the spec's camelCase JSON
  # convention (§5.5), matching the `"taskId"` of the §11.6 example.
  defp metadata(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {Naming.to_camel(to_string(k)), to_string(v)} end)
  end

  defp metadata(_), do: nil

  defp maybe_put(map, _key, empty) when empty in [nil, %{}, []], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
