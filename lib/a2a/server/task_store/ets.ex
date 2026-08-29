defmodule A2A.Server.TaskStore.ETS do
  @moduledoc "Default ETS-backed `A2A.Server.TaskStore`. A GenServer owns a public named `:set` table."
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

  defp key(id, %A2A.Scope{tenant: t, owner: o}), do: {t, o, id}
end
