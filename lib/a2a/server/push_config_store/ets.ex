defmodule A2A.Server.PushConfigStore.ETS do
  @moduledoc false
  use GenServer
  @behaviour A2A.Server.PushConfigStore

  alias A2A.Types.TaskPushNotificationConfig, as: Cfg

  @table __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl A2A.Server.PushConfigStore
  def put(%Cfg{task_id: task_id, id: id} = config, scope) do
    true = :ets.insert(@table, {key(task_id, id, scope), config})
    :ok
  end

  @impl A2A.Server.PushConfigStore
  def get(task_id, id, scope) do
    case :ets.lookup(@table, key(task_id, id, scope)) do
      [{_k, config}] -> {:ok, config}
      [] -> {:error, :not_found}
    end
  end

  @impl A2A.Server.PushConfigStore
  def list(task_id, %A2A.Scope{tenant: t, owner: o} = _scope) do
    configs =
      @table
      |> :ets.match_object({{t, o, task_id, :_}, :_})
      |> Enum.map(fn {_k, config} -> config end)

    {:ok, configs}
  end

  @impl A2A.Server.PushConfigStore
  def delete(task_id, id, scope) do
    :ets.delete(@table, key(task_id, id, scope))
    :ok
  end

  defp key(task_id, id, %A2A.Scope{tenant: t, owner: o}), do: {t, o, task_id, id}
end
