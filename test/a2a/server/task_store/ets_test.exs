defmodule A2A.Server.TaskStore.ETSTest do
  use A2A.Server.TaskStore.ConformanceCase

  alias A2A.Server.TaskStore.ETS
  alias A2A.Types.{Task, TaskStatus}

  setup do
    start_supervised!(A2A.Server.TaskStore.ETS)
    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{store: A2A.Server.TaskStore.ETS}
  end

  defp task(id, opts \\ []) do
    %Task{
      id: id,
      context_id: Keyword.get(opts, :context_id, "c"),
      status: %TaskStatus{
        state: Keyword.get(opts, :state, :working),
        timestamp: Keyword.get(opts, :ts)
      }
    }
  end

  describe "list/2" do
    setup do
      scope = A2A.Scope.default()
      :ok = ETS.save(task("a", context_id: "c1", state: :working), scope)
      :ok = ETS.save(task("b", context_id: "c1", state: :completed), scope)
      :ok = ETS.save(task("c", context_id: "c2", state: :working), scope)
      %{scope: scope}
    end

    test "no filters returns all in-scope tasks", %{scope: scope} do
      {:ok, tasks} = ETS.list(%{}, scope)
      assert Enum.map(tasks, & &1.id) |> Enum.sort() == ["a", "b", "c"]
    end

    test "filters by context_id", %{scope: scope} do
      {:ok, tasks} = ETS.list(%{context_id: "c1"}, scope)
      assert Enum.map(tasks, & &1.id) |> Enum.sort() == ["a", "b"]
    end

    test "filters by status", %{scope: scope} do
      {:ok, tasks} = ETS.list(%{status: :working}, scope)
      assert Enum.map(tasks, & &1.id) |> Enum.sort() == ["a", "c"]
    end

    test "filters by status_timestamp_after", %{scope: scope} do
      :ok = ETS.save(task("old", ts: ~U[2020-01-01 00:00:00Z]), scope)
      :ok = ETS.save(task("new", ts: ~U[2030-01-01 00:00:00Z]), scope)
      {:ok, tasks} = ETS.list(%{status_timestamp_after: ~U[2025-01-01 00:00:00Z]}, scope)
      assert "new" in Enum.map(tasks, & &1.id)
      refute "old" in Enum.map(tasks, & &1.id)
    end

    test "is scope-isolated", %{scope: scope} do
      other = %A2A.Scope{scope | owner: "someone-else"}
      :ok = ETS.save(task("z"), other)
      {:ok, tasks} = ETS.list(%{}, scope)
      refute "z" in Enum.map(tasks, & &1.id)
    end
  end
end
