defmodule A2A.Client do
  @moduledoc """
  A2A client. Build one with `connect/2`, then call the operation functions.
  The struct is a plain value — hold it, pass it, discard it; it starts no
  process. See `docs/superpowers/specs/2026-09-01-a2a-client-design.md`.
  """
  @type t :: %__MODULE__{
          agent_card: A2A.Types.AgentCard.t(),
          transport: module(),
          endpoint: String.t(),
          config: A2A.Client.Config.t()
        }
  defstruct [:agent_card, :transport, :endpoint, :config]
end
