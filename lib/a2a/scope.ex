defmodule A2A.Scope do
  @moduledoc """
  Tenant/owner scope threaded through the persistence behaviours. Single-tenant
  agents use `default/0` and can ignore it; multi-tenant deployments filter by it.
  """
  @type t :: %__MODULE__{tenant: String.t() | nil, owner: String.t() | nil}
  defstruct tenant: nil, owner: nil

  @spec default() :: t()
  def default, do: %__MODULE__{}
end
