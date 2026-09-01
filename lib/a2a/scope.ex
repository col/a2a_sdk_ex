defmodule A2A.Scope do
  @moduledoc """
  The tenant/owner scope passed to `A2A.Server.TaskStore` callbacks (fields
  `tenant` and `owner`). `default/0` returns an empty scope for single-tenant
  agents.
  """
  @type t :: %__MODULE__{tenant: String.t() | nil, owner: String.t() | nil}
  defstruct tenant: nil, owner: nil

  @spec default() :: t()
  def default, do: %__MODULE__{}
end
