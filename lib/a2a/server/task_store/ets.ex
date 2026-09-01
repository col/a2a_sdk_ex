defmodule A2A.Server.TaskStore.ETS do
  @moduledoc false
  use GenServer
  @behaviour A2A.Server.TaskStore

  @table __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl A2A.Server.TaskStore
  def save(%A2A.Types.Task{id: id} = task, scope) do
    true = :ets.insert(@table, {key(id, scope), task})
    :ok
  end

  @impl A2A.Server.TaskStore
  def get(id, scope) do
    case :ets.lookup(@table, key(id, scope)) do
      [{_k, task}] -> {:ok, task}
      [] -> {:error, :not_found}
    end
  end

  @impl A2A.Server.TaskStore
  def delete(id, scope) do
    :ets.delete(@table, key(id, scope))
    :ok
  end

  @impl A2A.Server.TaskStore
  def list(filter, %A2A.Scope{tenant: t, owner: o} = _scope) do
    tasks =
      @table
      |> :ets.match_object({{t, o, :_}, :_})
      |> Enum.map(fn {_k, task} -> task end)
      |> Enum.filter(&matches?(&1, filter))

    {:ok, tasks}
  end

  defp key(id, %A2A.Scope{tenant: t, owner: o}), do: {t, o, id}

  defp matches?(task, filter) do
    match_context?(task, filter[:context_id]) and
      match_status?(task, filter[:status]) and
      match_after?(task, filter[:status_timestamp_after])
  end

  defp match_context?(_task, nil), do: true
  defp match_context?(task, ctx), do: task.context_id == ctx

  defp match_status?(_task, nil), do: true
  defp match_status?(task, status), do: task.status.state == status

  defp match_after?(_task, nil), do: true
  defp match_after?(%{status: %{timestamp: nil}}, _after), do: false

  defp match_after?(task, after_dt),
    do: DateTime.compare(task.status.timestamp, after_dt) == :gt
end
