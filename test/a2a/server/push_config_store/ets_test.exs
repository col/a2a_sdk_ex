defmodule A2A.Server.PushConfigStore.ETSTest do
  use ExUnit.Case, async: false
  alias A2A.Server.PushConfigStore.ETS
  alias A2A.Types.TaskPushNotificationConfig, as: Cfg

  setup do
    start_supervised!(ETS)
    :ets.delete_all_objects(ETS)
    :ok
  end

  defp cfg(task_id, id, url \\ "https://h/cb"),
    do: %Cfg{task_id: task_id, id: id, url: url}

  test "put then get returns the stored config" do
    scope = A2A.Scope.default()
    :ok = ETS.put(cfg("t1", "c1"), scope)
    assert {:ok, %Cfg{id: "c1", task_id: "t1"}} = ETS.get("t1", "c1", scope)
  end

  test "get is not_found for unknown id" do
    assert {:error, :not_found} = ETS.get("t1", "missing", A2A.Scope.default())
  end

  test "list returns all configs for a task, put upserts on {task_id,id}" do
    scope = A2A.Scope.default()
    :ok = ETS.put(cfg("t1", "c1", "https://h/1"), scope)
    :ok = ETS.put(cfg("t1", "c2", "https://h/2"), scope)
    :ok = ETS.put(cfg("t1", "c1", "https://h/1b"), scope)
    {:ok, configs} = ETS.list("t1", scope)
    assert length(configs) == 2
    assert Enum.any?(configs, &(&1.id == "c1" and &1.url == "https://h/1b"))
  end

  test "delete removes and is idempotent" do
    scope = A2A.Scope.default()
    :ok = ETS.put(cfg("t1", "c1"), scope)
    assert :ok = ETS.delete("t1", "c1", scope)
    assert {:error, :not_found} = ETS.get("t1", "c1", scope)
    assert :ok = ETS.delete("t1", "c1", scope)
  end

  test "scope isolates configs" do
    a = %A2A.Scope{tenant: "a", owner: nil}
    b = %A2A.Scope{tenant: "b", owner: nil}
    :ok = ETS.put(cfg("t1", "c1"), a)
    assert {:ok, []} = ETS.list("t1", b)
    assert {:ok, [_]} = ETS.list("t1", a)
  end
end
