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
end
