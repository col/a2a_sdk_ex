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

  describe "to_jsonrpc/1" do
    test "maps known semantic codes to A2A JSON-RPC codes" do
      assert %{"code" => -32_001} = A2A.Error.to_jsonrpc(A2A.Error.not_found("t"))
      assert %{"code" => -32_002} = A2A.Error.to_jsonrpc(A2A.Error.terminal_task("t"))

      assert %{"code" => -32_002} =
               A2A.Error.to_jsonrpc(%A2A.Error{code: :task_in_progress, message: "x"})

      assert %{"code" => -32_004} =
               A2A.Error.to_jsonrpc(%A2A.Error{code: :unsupported_operation, message: "x"})
    end

    test "unmapped or internal codes fall back to -32603" do
      assert %{"code" => -32_603} =
               A2A.Error.to_jsonrpc(%A2A.Error{code: :internal_error, message: "x"})

      assert %{"code" => -32_603} =
               A2A.Error.to_jsonrpc(%A2A.Error{code: :timeout, message: "x"})

      assert %{"code" => -32_603} =
               A2A.Error.to_jsonrpc(%A2A.Error{code: :something_new, message: "x"})
    end

    test "carries message and includes data only when present" do
      obj = A2A.Error.to_jsonrpc(A2A.Error.not_found("t-9"))
      assert obj["message"] =~ "t-9"
      assert obj["data"] == %{task_id: "t-9"}

      bare = A2A.Error.to_jsonrpc(%A2A.Error{code: :internal_error, message: "boom", data: nil})
      refute Map.has_key?(bare, "data")
    end
  end
end
