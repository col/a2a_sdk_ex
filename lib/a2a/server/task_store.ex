defmodule A2A.Server.TaskStore do
  @moduledoc """
  Persistence behaviour for the durable task projection. The store is a *projection*,
  not the source of truth for a running task (that is the execution process). ETS is the default.

  `save/2`, `get/2`, `delete/2` are the core callbacks. `list/2` is declared
  `@optional_callbacks` for the benefit of alternate stores that don't need
  querying — `A2A.Server.TaskStore.ETS` implements it as a scoped, filtered
  scan; sorting, cursoring, and pagination stay in
  `A2A.Server.DefaultHandler.list_tasks/2` (see ADR-0011), keeping the store a
  dumb query surface.
  """
  alias A2A.Types.Task

  @callback save(Task.t(), A2A.Scope.t()) :: :ok | {:error, term()}
  @callback get(String.t(), A2A.Scope.t()) :: {:ok, Task.t()} | {:error, :not_found}
  @callback delete(String.t(), A2A.Scope.t()) :: :ok | {:error, term()}
  @callback list(map(), A2A.Scope.t()) :: {:ok, [Task.t()]} | {:error, term()}

  @optional_callbacks list: 2
end
