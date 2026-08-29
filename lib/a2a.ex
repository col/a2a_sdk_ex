defmodule A2A do
  @moduledoc """
  Elixir SDK for building A2A (Agent2Agent) compliant agents.

  Provides the typed data model (`A2A.Types.*`), the `A2A.JSON` proto3-JSON codec,
  and the server runtime core (`A2A.Server.*`): a mountable OTP supervision tree,
  process-per-task execution, a PubSub event path, and an ETS-backed `TaskStore`.
  See `A2A.Server.Supervisor` and `A2A.Server.DefaultHandler`.
  """
end
