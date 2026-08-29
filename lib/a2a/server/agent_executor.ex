defmodule A2A.Server.AgentExecutor do
  @moduledoc """
  The behaviour an agent author implements. `execute/2` runs inside the task's
  execution process and emits events through the `TaskUpdater`; it never returns output.
  """
  alias A2A.Server.RequestContext

  # TaskUpdater arrives in Task 6; dialyzer fails the build on a forward
  # reference to an undefined struct type, so `updater` is typed as `term()`
  # here until then.
  @callback execute(RequestContext.t(), updater :: term()) :: :ok | {:error, term()}
  @callback cancel(RequestContext.t(), updater :: term()) :: :ok

  @optional_callbacks cancel: 2
end
