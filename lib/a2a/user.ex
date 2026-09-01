defmodule A2A.User do
  @moduledoc """
  The caller identity on an `A2A.Server.RequestContext` (fields `id`,
  `authenticated?`, and `claims`). `anonymous/0` returns an unauthenticated user.
  """
  @type t :: %__MODULE__{id: String.t() | nil, authenticated?: boolean(), claims: map()}
  defstruct id: nil, authenticated?: false, claims: %{}

  @spec anonymous() :: t()
  def anonymous, do: %__MODULE__{}
end
