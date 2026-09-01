defmodule A2A.Scope do
  @moduledoc false
  @type t :: %__MODULE__{tenant: String.t() | nil, owner: String.t() | nil}
  defstruct tenant: nil, owner: nil

  @spec default() :: t()
  def default, do: %__MODULE__{}
end
