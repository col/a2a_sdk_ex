defmodule A2A.User do
  @moduledoc "The authenticated caller surfaced to an executor. Phase 1 ships only the anonymous default."
  @type t :: %__MODULE__{id: String.t() | nil, authenticated?: boolean(), claims: map()}
  defstruct id: nil, authenticated?: false, claims: %{}

  @spec anonymous() :: t()
  def anonymous, do: %__MODULE__{}
end
