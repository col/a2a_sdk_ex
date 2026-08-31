defmodule ComplianceServer.ScenariosTest do
  use ExUnit.Case, async: true

  alias ComplianceServer.Scenarios

  doctest ComplianceServer.Scenarios

  # The TCK signals the behaviour it wants in-band, via the `messageId` prefix.
  # Every pair below is transcribed from the a2a-tck Gherkin sources — keep them
  # in step with `scenarios/core_operations.feature` and `scenarios/streaming.feature`.
  @core [
    {"tck-complete-task", :complete_task},
    {"tck-artifact-text", :artifact_text},
    {"tck-artifact-file", :artifact_file},
    {"tck-artifact-file-url", :artifact_file_url},
    {"tck-artifact-data", :artifact_data},
    {"tck-input-required", :input_required},
    {"tck-reject-task", :reject_task}
  ]

  @streaming [
    {"tck-stream-001", :stream_001},
    {"tck-stream-002", :stream_002},
    {"tck-stream-003", :stream_003},
    {"tck-stream-ordering-001", :stream_ordering_001},
    {"tck-stream-artifact-text", :stream_artifact_text},
    {"tck-stream-artifact-file", :stream_artifact_file},
    {"tck-stream-artifact-chunked", :stream_artifact_chunked},
    {"test-resubscribe-message-id", :resubscribe_long_running}
  ]

  describe "resolve/1" do
    test "resolves every core_operations.feature prefix" do
      for {prefix, scenario} <- @core do
        assert Scenarios.resolve(prefix <> "-19af2c") == scenario
      end
    end

    test "resolves every streaming.feature prefix" do
      for {prefix, scenario} <- @streaming do
        assert Scenarios.resolve(prefix <> "-19af2c") == scenario
      end
    end

    test "falls back to :default for ids with no scenario" do
      # The TCK sends plenty of these — `tck-multi-004`, `tck-nonexistent-*`,
      # `tck-error-code-005` — and expects ordinary task behaviour.
      assert Scenarios.resolve("tck-multi-004-19af2c") == :default
      assert Scenarios.resolve("whatever") == :default
    end

    test "falls back to :default for the unimplemented message-response scenario" do
      # Returning a bare Message needs an SDK path that does not exist yet.
      assert Scenarios.resolve("tck-message-response-19af2c") == :default
    end

    test "falls back to :default when the message carries no id" do
      assert Scenarios.resolve(nil) == :default
    end
  end
end
