defmodule A2A.Test.Coverage do
  @moduledoc """
  Coverage manifest for the proto-conformance harness. `covered` is DERIVED from
  the loaded `A2A.Types.*` modules (so it cannot drift from the code); `@deferred`
  is the explicit list of messages postponed to Phase 4.
  """

  alias A2A.Types.Enums

  @deferred [
    # Phase 4 — Push notifications & task listing
    %{
      message: "TaskPushNotificationConfig",
      phase: 4,
      reason: "Phase 4: push notifications & task listing"
    },
    %{
      message: "GetTaskPushNotificationConfigRequest",
      phase: 4,
      reason: "Phase 4: push notifications & task listing"
    },
    %{
      message: "DeleteTaskPushNotificationConfigRequest",
      phase: 4,
      reason: "Phase 4: push notifications & task listing"
    },
    %{
      message: "ListTaskPushNotificationConfigsRequest",
      phase: 4,
      reason: "Phase 4: push notifications & task listing"
    },
    %{
      message: "ListTaskPushNotificationConfigsResponse",
      phase: 4,
      reason: "Phase 4: push notifications & task listing"
    },
    %{message: "ListTasksRequest", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "ListTasksResponse", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "CancelTaskRequest", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{
      message: "SubscribeToTaskRequest",
      phase: 4,
      reason: "Phase 4: push notifications & task listing"
    }
  ]

  @spec deferred() :: [%{message: String.t(), phase: 4, reason: String.t()}]
  def deferred, do: @deferred

  @spec deferred_names() :: MapSet.t(String.t())
  def deferred_names, do: MapSet.new(@deferred, & &1.message)

  @doc "Proto message names with a hand-written struct (derived from loaded modules)."
  @spec covered_messages() :: MapSet.t(String.t())
  def covered_messages do
    ensure_loaded()

    for {mod, _} <- :code.all_loaded(),
        mod |> Atom.to_string() |> String.starts_with?("Elixir.A2A.Types."),
        function_exported?(mod, :__a2a_proto_name__, 0),
        into: MapSet.new() do
      mod.__a2a_proto_name__()
    end
  end

  @doc "Covered messages plus covered enum type names."
  @spec covered() :: MapSet.t(String.t())
  def covered, do: MapSet.union(covered_messages(), MapSet.new(Enums.proto_names()))

  @spec all_expected() :: MapSet.t(String.t())
  def all_expected, do: MapSet.union(covered(), deferred_names())

  # `:code.all_loaded/0` only sees loaded modules; force-load the A2A.Types tree.
  defp ensure_loaded do
    {:ok, mods} = :application.get_key(:a2a, :modules)
    Enum.each(mods, &Code.ensure_loaded/1)
  end
end
