defmodule A2A.Server.Agent.ResultTest do
  use ExUnit.Case, async: true

  import A2A.Server.Agent.Result
  alias A2A.Server.Agent.Result
  alias A2A.Types.Part

  test "reply/0 seeds an empty result" do
    assert %Result{directives: [], message: nil, terminal: nil} = reply()
  end

  test "artifact/4 appends a directive in author order with normalized parts" do
    r = reply() |> artifact("a", "one") |> artifact("b", ["two", Part.text("three")])

    assert [
             {:artifact, "a", [%Part{kind: :text, text: "one"}], []},
             {:artifact, "b", [%Part{text: "two"}, %Part{text: "three"}], []}
           ] = Result.directives(r)
  end

  test "artifact/4 carries id and metadata opts" do
    r = reply() |> artifact("a", "x", id: "id-1", metadata: %{"k" => "v"})
    assert [{:artifact, "a", [_], [id: "id-1", metadata: %{"k" => "v"}]}] = Result.directives(r)
  end

  test "stream/4 stores the enumerable lazily (unconsumed)" do
    enum = Stream.map([1, 2], fn _ -> raise "must not enumerate in builder" end)
    r = reply() |> stream("s", enum)
    assert [{:stream, "s", ^enum, []}] = Result.directives(r)
  end

  test "message/3 sets the status message" do
    r = reply() |> message("hi", metadata: %{"m" => 1})
    assert %Result{message: {[%Part{text: "hi"}], [metadata: %{"m" => 1}]}} = r
  end

  test "complete/1 sets a :completed terminal; message: opt sets the message" do
    assert %Result{terminal: {:completed, []}, message: nil} = reply() |> complete()

    r = reply() |> complete(message: "done", metadata: %{"n" => 2})

    assert %Result{
             terminal: {:completed, []},
             message: {[%Part{text: "done"}], [metadata: %{"n" => 2}]}
           } = r
  end

  test "input_required/1, reject/2, fail/2 set their terminals" do
    assert %Result{terminal: {:input_required, []}} = reply() |> input_required()

    assert %Result{terminal: {:rejected, []}, message: {[%Part{text: "no"}], []}} =
             reply() |> reject("no")

    assert %Result{terminal: {:failed, []}, message: {[%Part{text: "boom"}], []}} =
             reply() |> fail("boom")
  end

  test "reject/1 with nil reason sets no message" do
    assert %Result{terminal: {:rejected, []}, message: nil} = reply() |> reject()
  end

  test "setting a second terminal raises" do
    assert_raise ArgumentError, ~r/terminal already set/, fn ->
      reply() |> complete() |> fail("x")
    end
  end
end
