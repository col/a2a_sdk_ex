defmodule A2A.User do
  @moduledoc false
  @type t :: %__MODULE__{id: String.t() | nil, authenticated?: boolean(), claims: map()}
  defstruct id: nil, authenticated?: false, claims: %{}

  @spec anonymous() :: t()
  def anonymous, do: %__MODULE__{}
end
