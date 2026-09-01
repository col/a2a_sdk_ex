defmodule A2A.Client.ErrorTest do
  use ExUnit.Case, async: true
  alias A2A.Client.Error, as: CE

  test "jsonrpc A2A-specific code maps to atom + message" do
    e =
      CE.from_jsonrpc(%{
        "code" => -32_001,
        "message" => "task not found: t1",
        "data" => [
          %{
            "@type" => "type.googleapis.com/google.rpc.ErrorInfo",
            "reason" => "TASK_NOT_FOUND",
            "domain" => "a2a-protocol.org",
            "metadata" => %{"taskId" => "t1"}
          }
        ]
      })

    assert %A2A.Error{code: :task_not_found, message: "task not found: t1"} = e
    assert e.data == %{"taskId" => "t1"}
  end

  test "jsonrpc standard code maps to atom" do
    assert %A2A.Error{code: :method_not_found} =
             CE.from_jsonrpc(%{"code" => -32_601, "message" => "nope"})
  end

  test "jsonrpc unknown code falls back to internal_error, preserving message" do
    assert %A2A.Error{code: :internal_error, message: "weird"} =
             CE.from_jsonrpc(%{"code" => -40_000, "message" => "weird"})
  end

  test "rest body maps via ErrorInfo reason" do
    body = %{
      "error" => %{
        "code" => 404,
        "status" => "NOT_FOUND",
        "message" => "task not found: t1",
        "details" => [
          %{
            "@type" => "type.googleapis.com/google.rpc.ErrorInfo",
            "reason" => "TASK_NOT_FOUND",
            "metadata" => %{"taskId" => "t1"}
          }
        ]
      }
    }

    assert %A2A.Error{code: :task_not_found, data: %{"taskId" => "t1"}} = CE.from_rest(404, body)
  end

  test "rest without ErrorInfo falls back to status" do
    assert %A2A.Error{code: :method_not_found} =
             CE.from_rest(404, %{
               "error" => %{"code" => 404, "status" => "NOT_FOUND", "message" => "x"}
             })
  end

  test "transport fault" do
    assert %A2A.Error{code: :internal_error} = CE.from_transport({:closed, :econnrefused})
  end
end
