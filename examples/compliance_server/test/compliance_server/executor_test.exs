defmodule ComplianceServer.ExecutorTest do
  @moduledoc """
  Drives the executor through the real server so the assertions match what the
  TCK actually inspects: the assembled `Task`, not the events behind it.

  Reuses the tree the application already started: `A2A.Server.TaskStore.ETS` is
  globally named, so a second `A2A.Server.Supervisor` collides on `:already_started`.
  That also forces `async: false` — the store is shared across these tests.
  """
  use ExUnit.Case, async: false

  alias A2A.Server.DefaultHandler
  alias A2A.Types.{Message, Part, SendMessageRequest, Task}

  setup do
    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{server: A2A.Server.handle(ComplianceServer.Agent)}
  end

  # Sends one message whose id carries `prefix`, returning the assembled task.
  defp run(server, prefix) do
    req = %SendMessageRequest{
      message: %Message{
        message_id: prefix <> "-19af2c",
        role: :user,
        parts: [Part.text("TCK prerequisite task creation")]
      }
    }

    assert {:ok, %Task{} = task} = DefaultHandler.send_message(server, req)
    task
  end

  defp only_part(%Task{artifacts: [artifact]}) do
    assert artifact.artifact_id not in [nil, ""], "artifact must carry an artifactId"
    assert [part] = artifact.parts
    part
  end

  describe "task states" do
    test "tck-complete-task completes the task", %{server: server} do
      assert %Task{status: %{state: :completed}} = run(server, "tck-complete-task")
    end

    test "tck-input-required leaves the task awaiting input", %{server: server} do
      assert %Task{status: %{state: :input_required}} = run(server, "tck-input-required")
    end

    test "tck-reject-task rejects the task", %{server: server} do
      assert %Task{status: %{state: :rejected}} = run(server, "tck-reject-task")
    end

    test "an unrecognised id completes the task like any other", %{server: server} do
      assert %Task{status: %{state: :completed}} = run(server, "tck-multi-004")
    end
  end

  describe "artifacts" do
    test "tck-artifact-text carries the exact text the TCK expects", %{server: server} do
      part = server |> run("tck-artifact-text") |> only_part()

      assert %Part{kind: :text, text: "Generated text content"} = part
    end

    test "tck-artifact-file carries a named, typed file part", %{server: server} do
      part = server |> run("tck-artifact-file") |> only_part()

      assert %Part{kind: :raw, filename: "output.txt", media_type: "text/plain"} = part
      assert is_binary(part.raw)
    end

    test "tck-artifact-file-url carries a url part, not a raw one", %{server: server} do
      part = server |> run("tck-artifact-file-url") |> only_part()

      assert %Part{
               kind: :url,
               url: "https://example.com/output.txt",
               filename: "output.txt",
               media_type: "text/plain"
             } = part
    end

    test "tck-artifact-data carries the exact data the TCK expects", %{server: server} do
      part = server |> run("tck-artifact-data") |> only_part()

      assert %Part{kind: :data, data: %{"key" => "value", "count" => 42}} = part
    end
  end

  describe "hold_ms/0" do
    setup do
      on_exit(fn -> System.delete_env("TCK_STREAMING_TIMEOUT") end)
    end

    test "defaults to twice the TCK's default streaming timeout" do
      System.delete_env("TCK_STREAMING_TIMEOUT")
      assert ComplianceServer.Executor.hold_ms() == 4_000
    end

    test "honours a fractional TCK_STREAMING_TIMEOUT" do
      System.put_env("TCK_STREAMING_TIMEOUT", "5.0")
      assert ComplianceServer.Executor.hold_ms() == 10_000
    end

    test "accepts an integer-valued TCK_STREAMING_TIMEOUT" do
      # `TCK_STREAMING_TIMEOUT=2` is a legal value; String.to_float/1 raises on it,
      # which would kill the executor mid-scenario.
      System.put_env("TCK_STREAMING_TIMEOUT", "2")
      assert ComplianceServer.Executor.hold_ms() == 4_000
    end

    test "falls back to the default when TCK_STREAMING_TIMEOUT is unparseable" do
      System.put_env("TCK_STREAMING_TIMEOUT", "soon")
      assert ComplianceServer.Executor.hold_ms() == 4_000
    end
  end

  describe "streaming scenarios, assembled" do
    test "tck-stream-001 completes with its streamed artifact", %{server: server} do
      task = run(server, "tck-stream-001")

      assert %Task{status: %{state: :completed}} = task
      assert %Part{kind: :text, text: "Stream hello from TCK"} = only_part(task)
    end

    test "tck-stream-artifact-chunked merges both chunks into one artifact", %{server: server} do
      task = run(server, "tck-stream-artifact-chunked")

      assert %Task{status: %{state: :completed}, artifacts: [artifact]} = task
      assert Enum.map(artifact.parts, & &1.text) == ["chunk-1 ", "chunk-2"]
    end
  end
end
