defmodule A2A.Server.PushConfigStore do
  @moduledoc false
  alias A2A.Types.TaskPushNotificationConfig, as: Cfg

  @callback put(Cfg.t(), A2A.Scope.t()) :: :ok | {:error, term()}
  @callback get(task_id :: String.t(), id :: String.t(), A2A.Scope.t()) ::
              {:ok, Cfg.t()} | {:error, :not_found}
  @callback list(task_id :: String.t(), A2A.Scope.t()) :: {:ok, [Cfg.t()]}
  @callback delete(task_id :: String.t(), id :: String.t(), A2A.Scope.t()) :: :ok
end
