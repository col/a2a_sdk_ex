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

  describe "not_cancelable/1" do
    test "builds a :task_not_cancelable error carrying the id" do
      err = A2A.Error.not_cancelable("t1")
      assert err.code == :task_not_cancelable
      assert err.data == %{task_id: "t1"}
      assert err.message =~ "t1"
    end
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

  describe "to_jsonrpc/1 (unchanged mappings)" do
    test "known codes map to their JSON-RPC integers" do
      assert A2A.Error.to_jsonrpc(A2A.Error.not_found("t"))["code"] == -32_001
      assert A2A.Error.to_jsonrpc(A2A.Error.not_cancelable("t"))["code"] == -32_002
      assert A2A.Error.to_jsonrpc(%A2A.Error{code: :unsupported_operation})["code"] == -32_004
    end

    test "unknown/internal code falls back to -32603" do
      assert A2A.Error.to_jsonrpc(%A2A.Error{code: :internal_error})["code"] == -32_603
      assert A2A.Error.to_jsonrpc(%A2A.Error{code: :something_else})["code"] == -32_603
    end
  end

  describe "to_rest/1" do
    test "task_not_found -> 404 with google.rpc.Status body + ErrorInfo" do
      {status, body} = A2A.Error.to_rest(A2A.Error.not_found("abc"))
      assert status == 404
      assert body["code"] == 5
      assert body["message"] =~ "abc"
      assert [detail] = body["details"]
      assert detail["@type"] == "type.googleapis.com/google.rpc.ErrorInfo"
      assert detail["reason"] == "TASK_NOT_FOUND"
      assert detail["domain"] == "a2a-protocol.org"
      assert detail["metadata"] == %{"task_id" => "abc"}
    end

    test "status mapping per spec §5.4" do
      assert {400, _} = A2A.Error.to_rest(A2A.Error.not_cancelable("t"))
      assert {400, _} = A2A.Error.to_rest(%A2A.Error{code: :unsupported_operation})
      assert {400, _} = A2A.Error.to_rest(%A2A.Error{code: :content_type_not_supported})
      assert {500, _} = A2A.Error.to_rest(%A2A.Error{code: :invalid_agent_response})
      assert {500, _} = A2A.Error.to_rest(%A2A.Error{code: :internal_error})
    end

    test "nil data omits metadata" do
      {_status, body} = A2A.Error.to_rest(%A2A.Error{code: :internal_error, message: "boom"})
      assert [detail] = body["details"]
      refute Map.has_key?(detail, "metadata")
    end
  end
end
