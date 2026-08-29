defmodule A2A.Server.TaskStore.ConformanceCase do
  @moduledoc "Shared behaviour-conformance suite for any A2A.Server.TaskStore. `use` it and set @store."
  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case, async: false
      alias A2A.Scope
      alias A2A.Types.{Task, TaskStatus}

      defp sample_task(id),
        do: %Task{id: id, context_id: "ctx", status: %TaskStatus{state: :working}}

      test "get on a missing task returns {:error, :not_found}", %{store: store} do
        assert {:error, :not_found} = store.get("missing", Scope.default())
      end

      test "save then get round-trips the task", %{store: store} do
        task = sample_task("t-1")
        assert :ok = store.save(task, Scope.default())
        assert {:ok, ^task} = store.get("t-1", Scope.default())
      end

      test "save overwrites an existing task", %{store: store} do
        assert :ok = store.save(sample_task("t-2"), Scope.default())
        updated = %{sample_task("t-2") | status: %A2A.Types.TaskStatus{state: :completed}}
        assert :ok = store.save(updated, Scope.default())
        assert {:ok, %Task{status: %{state: :completed}}} = store.get("t-2", Scope.default())
      end

      test "delete removes the task", %{store: store} do
        assert :ok = store.save(sample_task("t-3"), Scope.default())
        assert :ok = store.delete("t-3", Scope.default())
        assert {:error, :not_found} = store.get("t-3", Scope.default())
      end

      test "scope isolates rows", %{store: store} do
        a = %Scope{tenant: "a"}
        b = %Scope{tenant: "b"}
        assert :ok = store.save(sample_task("shared"), a)
        assert {:error, :not_found} = store.get("shared", b)
        assert {:ok, _} = store.get("shared", a)
      end
    end
  end
end
