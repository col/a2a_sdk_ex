defmodule A2A.ErrorTest do
  use ExUnit.Case, async: true

  @error_info "type.googleapis.com/google.rpc.ErrorInfo"

  # The ErrorInfo entry both bindings must carry, wherever it lives.
  defp error_info(details) do
    assert [detail] = details
    assert detail["@type"] == @error_info
    assert detail["domain"] == "a2a-protocol.org"
    detail
  end

  describe "constructors" do
    test "not_found/1 carries the task id and a :task_not_found code" do
      err = A2A.Error.not_found("t-1")
      assert %A2A.Error{code: :task_not_found, data: %{task_id: "t-1"}} = err
      assert err.message =~ "t-1"
    end

    test "terminal_task/1 uses :task_not_continuable" do
      assert %A2A.Error{code: :task_not_continuable} = A2A.Error.terminal_task("t-2")
    end

    test "not_cancelable/1 builds a :task_not_cancelable error carrying the id" do
      err = A2A.Error.not_cancelable("t1")
      assert err.code == :task_not_cancelable
      assert err.data == %{task_id: "t1"}
      assert err.message =~ "t1"
    end

    test "is a raisable exception" do
      assert_raise A2A.Error, fn -> raise A2A.Error.not_found("t-3") end
    end
  end

  describe "to_jsonrpc/1 codes (spec §5.4)" do
    test "A2A errors map to their -32001..-32009 codes" do
      assert code(:task_not_found) == -32_001
      assert code(:task_not_cancelable) == -32_002
      assert code(:push_notification_not_supported) == -32_003
      assert code(:unsupported_operation) == -32_004
      assert code(:content_type_not_supported) == -32_005
      assert code(:invalid_agent_response) == -32_006
      assert code(:extended_agent_card_not_configured) == -32_007
      assert code(:extension_support_required) == -32_008
      assert code(:version_not_supported) == -32_009
    end

    test "terminal-task and busy-task codes are UnsupportedOperation" do
      # Spec §3.4/§3.6: messages to, and subscribes on, a terminal task return
      # UnsupportedOperationError — not a code of our own invention.
      assert code(:task_not_continuable) == -32_004
      assert code(:task_in_progress) == -32_004
    end

    test "standard JSON-RPC errors keep their own codes" do
      assert code(:invalid_params) == -32_602
      assert code(:internal_error) == -32_603
      assert code(:timeout) == -32_603
    end

    test "an unmapped code falls back to -32603" do
      assert code(:something_new) == -32_603
    end
  end

  describe "to_jsonrpc/1 data (spec §9.5)" do
    test "an A2A error carries an ErrorInfo array, not a bare map" do
      obj = A2A.Error.to_jsonrpc(A2A.Error.not_found("t-9"))

      assert obj["message"] =~ "t-9"
      assert is_list(obj["data"])
      assert %{"reason" => "TASK_NOT_FOUND"} = error_info(obj["data"])
    end

    test "the error's data map becomes ErrorInfo metadata, camelCased" do
      detail =
        A2A.Error.not_found("abc")
        |> A2A.Error.to_jsonrpc()
        |> Map.fetch!("data")
        |> error_info()

      assert detail["metadata"] == %{"taskId" => "abc"}
    end

    test "an A2A error with no data still carries ErrorInfo, without metadata" do
      detail =
        %A2A.Error{code: :unsupported_operation, message: "nope"}
        |> A2A.Error.to_jsonrpc()
        |> Map.fetch!("data")
        |> error_info()

      refute Map.has_key?(detail, "metadata")
    end

    test "standard errors keep a plain data payload" do
      # §9.5's own example shows a bare object for MethodNotFound; these errors
      # have no A2A reason, so there is no ErrorInfo to wrap.
      obj = A2A.Error.to_jsonrpc(%A2A.Error{code: :invalid_params, message: "bad", data: %{a: 1}})
      assert obj["data"] == %{a: 1}

      bare = A2A.Error.to_jsonrpc(%A2A.Error{code: :internal_error, message: "boom", data: nil})
      refute Map.has_key?(bare, "data")
    end
  end

  describe "to_rest/1 status codes (spec §5.4)" do
    test "each A2A error maps to its HTTP status" do
      assert status(:task_not_found) == 404
      assert status(:task_not_cancelable) == 409
      assert status(:push_notification_not_supported) == 400
      assert status(:unsupported_operation) == 400
      assert status(:content_type_not_supported) == 415
      assert status(:invalid_agent_response) == 502
      assert status(:extended_agent_card_not_configured) == 400
      assert status(:extension_support_required) == 400
      assert status(:version_not_supported) == 400
    end

    test "standard and unmapped errors" do
      assert status(:invalid_params) == 400
      assert status(:internal_error) == 500
      assert status(:timeout) == 504
      assert status(:something_new) == 500
    end
  end

  describe "to_rest/1 body (AIP-193, spec §11.6)" do
    test "wraps the status in an `error` object whose code is the HTTP status" do
      {status, body} = A2A.Error.to_rest(A2A.Error.not_found("abc"))

      assert status == 404
      assert %{"error" => error} = body
      assert error["code"] == 404
      assert error["status"] == "NOT_FOUND"
      assert error["message"] =~ "abc"
    end

    test "the details array carries ErrorInfo with camelCased metadata" do
      {_status, %{"error" => error}} = A2A.Error.to_rest(A2A.Error.not_found("abc"))
      detail = error_info(error["details"])

      assert detail["reason"] == "TASK_NOT_FOUND"
      assert detail["metadata"] == %{"taskId" => "abc"}
    end

    test "the gRPC status name follows the error, not the transport" do
      assert {409, %{"error" => %{"status" => "FAILED_PRECONDITION"}}} =
               A2A.Error.to_rest(A2A.Error.not_cancelable("t"))

      assert {415, %{"error" => %{"status" => "INVALID_ARGUMENT"}}} =
               A2A.Error.to_rest(%A2A.Error{code: :content_type_not_supported})
    end

    test "an error with no data omits metadata" do
      {_status, %{"error" => error}} =
        A2A.Error.to_rest(%A2A.Error{code: :unsupported_operation, message: "nope"})

      refute Map.has_key?(error_info(error["details"]), "metadata")
    end

    test "standard errors carry no ErrorInfo" do
      {status, %{"error" => error}} =
        A2A.Error.to_rest(%A2A.Error{code: :invalid_params, message: "bad token"})

      assert status == 400
      assert error["code"] == 400
      assert error["status"] == "INVALID_ARGUMENT"
      refute Map.has_key?(error, "details")
    end
  end

  defp code(code), do: A2A.Error.to_jsonrpc(%A2A.Error{code: code, message: "x"})["code"]

  defp status(code) do
    {status, _body} = A2A.Error.to_rest(%A2A.Error{code: code, message: "x"})
    status
  end
end
