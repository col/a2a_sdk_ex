defmodule A2A.ErrorTest do
  use ExUnit.Case, async: true

  test "not_found/1 carries the task id and a :task_not_found code" do
    err = A2A.Error.not_found("t-1")
    assert %A2A.Error{code: :task_not_found, data: %{task_id: "t-1"}} = err
    assert err.message =~ "t-1"
  end

  test "terminal_task/1 uses :task_not_continuable" do
    assert %A2A.Error{code: :task_not_continuable} = A2A.Error.terminal_task("t-2")
  end

  test "is a raisable exception" do
    assert_raise A2A.Error, fn -> raise A2A.Error.not_found("t-3") end
  end
end
