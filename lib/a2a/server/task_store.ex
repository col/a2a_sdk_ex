defmodule A2A.Server.TaskStore do
  @moduledoc """
  Persistence behaviour for the durable task projection. The store is a *projection*,
  not the source of truth for a running task (that is the execution process). ETS is the default.

  Phase 1 implements `save/2`, `get/2`, `delete/2`. `list/2` is optional; the ETS
  store implements it as a scoped, filtered scan (see `A2A.Server.TaskStore.ETS`).
  """
  alias A2A.Types.Task

  @callback save(Task.t(), A2A.Scope.t()) :: :ok | {:error, term()}
  @callback get(String.t(), A2A.Scope.t()) :: {:ok, Task.t()} | {:error, :not_found}
  @callback delete(String.t(), A2A.Scope.t()) :: :ok | {:error, term()}
  @callback list(map(), A2A.Scope.t()) :: {:ok, [Task.t()]} | {:error, term()}

  @optional_callbacks list: 2
end
