defmodule ComplianceServer.Scenarios do
  @moduledoc """
  The TCK's in-band SUT contract: `messageId` prefix → scenario name.

  The a2a-tck suite has no side-channel for telling a SUT how to behave. It
  encodes the request in the `messageId` instead (`tck-<scenario>-<session>`),
  and `docs/SUT_REQUIREMENTS.md` names the Gherkin sources as the authority:

    * `scenarios/core_operations.feature`
    * `scenarios/streaming.feature`

  Keep this table in step with those files. Anything unmatched resolves to
  `:default`, which the executor completes like an ordinary task — that is the
  behaviour the feature files specify for unprefixed traffic, and most TCK tests
  only need *some* completed task.
  """

  @type scenario ::
          :complete_task
          | :artifact_text
          | :artifact_file
          | :artifact_file_url
          | :artifact_data
          | :input_required
          | :reject_task
          | :message_response
          | :stream_001
          | :stream_002
          | :stream_003
          | :stream_ordering_001
          | :stream_artifact_text
          | :stream_artifact_file
          | :stream_artifact_chunked
          | :resubscribe_long_running
          | :default

  @prefixes %{
    "tck-complete-task" => :complete_task,
    "tck-message-response" => :message_response,
    "tck-artifact-text" => :artifact_text,
    "tck-artifact-file" => :artifact_file,
    "tck-artifact-file-url" => :artifact_file_url,
    "tck-artifact-data" => :artifact_data,
    "tck-input-required" => :input_required,
    "tck-reject-task" => :reject_task,
    "tck-stream-001" => :stream_001,
    "tck-stream-002" => :stream_002,
    "tck-stream-003" => :stream_003,
    "tck-stream-ordering-001" => :stream_ordering_001,
    "tck-stream-artifact-text" => :stream_artifact_text,
    "tck-stream-artifact-file" => :stream_artifact_file,
    "tck-stream-artifact-chunked" => :stream_artifact_chunked,
    "test-resubscribe-message-id" => :resubscribe_long_running
  }

  # Longest prefix wins. `tck-artifact-file` is a prefix of
  # `tck-artifact-file-url`, so first-match-in-declaration-order would resolve
  # every file-url request to the plain file scenario.
  @ordered Enum.sort_by(@prefixes, fn {prefix, _} -> -byte_size(prefix) end)

  @doc """
  Resolves a `messageId` to the scenario the TCK is asking for.

  ## Examples

      iex> ComplianceServer.Scenarios.resolve("tck-input-required-19af2c")
      :input_required

      iex> ComplianceServer.Scenarios.resolve("tck-artifact-file-url-19af2c")
      :artifact_file_url

      iex> ComplianceServer.Scenarios.resolve("tck-multi-004-19af2c")
      :default

  """
  @spec resolve(String.t() | nil) :: scenario()
  def resolve(message_id) when is_binary(message_id) do
    Enum.find_value(@ordered, :default, fn {prefix, scenario} ->
      String.starts_with?(message_id, prefix) && scenario
    end)
  end

  def resolve(nil), do: :default
end
