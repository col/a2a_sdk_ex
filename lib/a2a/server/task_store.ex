defmodule A2A.Server.TaskStore do
  @moduledoc """
  Persistence behaviour for the durable task projection. The store is a
  *projection*, not the source of truth for a running task (that is the
  execution process). ETS-backed by default; provide a custom module via the
  `:store` option on `A2A.Server.Supervisor`.

  `save/2`, `get/2`, `delete/2` are the core callbacks. `list/2` is an
  `@optional_callback` for stores that don't need querying — sorting,
  cursoring, and pagination are handled by the caller, keeping the store a
  simple query surface.
  """
  alias A2A.Types.Task

  @callback save(Task.t(), A2A.Scope.t()) :: :ok | {:error, term()}
  @callback get(String.t(), A2A.Scope.t()) :: {:ok, Task.t()} | {:error, :not_found}
  @callback delete(String.t(), A2A.Scope.t()) :: :ok | {:error, term()}
  @callback list(map(), A2A.Scope.t()) :: {:ok, [Task.t()]} | {:error, term()}

  @optional_callbacks list: 2
end
