defmodule A2A.Client.SSETest do
  use ExUnit.Case, async: true
  alias A2A.Client.SSE

  defp collect(chunks), do: chunks |> SSE.frames() |> Enum.to_list()

  test "one event in one chunk" do
    assert collect(["data: {\"a\":1}\n\n"]) == ["{\"a\":1}"]
  end

  test "event split across chunks" do
    assert collect(["data: {\"a\"", ":1}\n\n"]) == ["{\"a\":1}"]
  end

  test "multiple events in one chunk" do
    assert collect(["data: 1\n\ndata: 2\n\n"]) == ["1", "2"]
  end

  test "ignores comments and keepalive blanks" do
    assert collect([": ping\n\n", "data: x\n\n"]) == ["x"]
  end

  test "multi-line data folds with newline joins" do
    assert collect(["data: a\ndata: b\n\n"]) == ["a\nb"]
  end
end
