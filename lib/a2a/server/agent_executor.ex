defmodule A2A.Server.AgentExecutor do
  @moduledoc """
  The behaviour an agent author implements. `execute/2` runs inside the task's
  execution process and emits events through the `TaskUpdater`; it never returns output.
  """
  alias A2A.Server.{RequestContext, TaskUpdater}

  @callback execute(RequestContext.t(), updater :: TaskUpdater.t()) :: :ok | {:error, term()}
  @callback cancel(RequestContext.t(), updater :: TaskUpdater.t()) :: :ok

  @optional_callbacks cancel: 2
end
