defmodule A2A.Error do
  @moduledoc """
  A protocol-level error. Phase 1 returns these tagged as `{:error, %A2A.Error{}}`
  from handler functions; JSON-RPC/HTTP status mapping arrives with the transports phase.
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

  @codes %{
    task_not_found: -32001,
    task_not_continuable: -32002,
    task_in_progress: -32002,
    task_not_cancelable: -32002,
    unsupported_operation: -32004,
    content_type_not_supported: -32005,
    invalid_agent_response: -32006
  }

  @doc """
  Renders this semantic error as a JSON-RPC 2.0 error object
  (`%{"code" => integer, "message" => binary, optional "data" => term}`).
  Unmapped or internal codes fall back to `-32603` (internal error).
  """
  @spec to_jsonrpc(t()) :: %{required(String.t()) => term()}
  def to_jsonrpc(%__MODULE__{code: code, message: message, data: data}) do
    base = %{"code" => Map.get(@codes, code, -32_603), "message" => message}
    if is_nil(data), do: base, else: Map.put(base, "data", data)
  end
end
