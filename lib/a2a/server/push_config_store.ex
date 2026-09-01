defmodule A2A.Server.PushConfigStore do
  @moduledoc """
  Persistence behaviour for push-notification configs, kept **separate** from
  `A2A.Server.TaskStore` so the `Task` type stays pure and a custom task store is
  not forced to implement push storage. Configs are keyed by `{scope, task_id, id}`.
  ETS is the default.
  """
  alias A2A.Types.TaskPushNotificationConfig, as: PushConfig

  @callback put(PushConfig.t(), A2A.Scope.t()) :: :ok | {:error, term()}
  @callback get(task_id :: String.t(), id :: String.t(), A2A.Scope.t()) ::
              {:ok, PushConfig.t()} | {:error, :not_found}
  @callback list(task_id :: String.t(), A2A.Scope.t()) :: {:ok, [PushConfig.t()]}
  @callback delete(task_id :: String.t(), id :: String.t(), A2A.Scope.t()) :: :ok
end
