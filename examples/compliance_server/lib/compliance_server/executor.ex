defmodule ComplianceServer.Executor do
  @moduledoc """
  Executes the behaviour the TCK asked for, named by the request's `messageId`
  prefix (see `ComplianceServer.Scenarios`).

  Each clause below transcribes one Gherkin scenario. Two ordering rules matter:

    * artifacts are emitted **before** the terminal status — a task freezes on
      reaching a terminal state, so an artifact added after `complete/2` is
      dropped by `A2A.Server.ResultAssembler`;
    * chunked artifacts reuse one `artifact_id`, since the assembler merges
      appended chunks by id.
  """
  @behaviour A2A.Server.AgentExecutor

  alias A2A.Server.{RequestContext, TaskUpdater}
  alias A2A.Types.Part
  alias ComplianceServer.Scenarios

  # The TCK's SUT contract: a resubscribe task must stay live for at least
  # 2 x TCK_STREAMING_TIMEOUT so the test can attach a second stream to it.
  @default_streaming_timeout 2.0

  @file_url "https://example.com/output.txt"
  @file_opts [filename: "output.txt", media_type: "text/plain"]

  @impl true
  def execute(%RequestContext{} = ctx, updater) do
    ctx.message.message_id
    |> Scenarios.resolve()
    |> run(ctx, updater)

    :ok
  end

  @impl true
  def cancel(_ctx, updater) do
    TaskUpdater.update_status(updater, :canceled)
    :ok
  end

  # --- core_operations.feature -------------------------------------------

  defp run(:complete_task, _ctx, u), do: TaskUpdater.complete(u, Part.text("Hello from TCK"))

  defp run(:artifact_text, _ctx, u) do
    u
    |> TaskUpdater.add_artifact(Part.text("Generated text content"))
    |> TaskUpdater.complete()
  end

  defp run(:artifact_file, _ctx, u) do
    u
    |> TaskUpdater.add_artifact(Part.raw("Generated file content", @file_opts))
    |> TaskUpdater.complete()
  end

  defp run(:artifact_file_url, _ctx, u) do
    u
    |> TaskUpdater.add_artifact(Part.url(@file_url, @file_opts))
    |> TaskUpdater.complete()
  end

  defp run(:artifact_data, _ctx, u) do
    u
    |> TaskUpdater.add_artifact(Part.data(%{"key" => "value", "count" => 42}))
    |> TaskUpdater.complete()
  end

  defp run(:input_required, _ctx, u), do: TaskUpdater.requires_input(u)

  defp run(:reject_task, _ctx, u), do: TaskUpdater.reject(u, "rejected")

  # --- streaming.feature --------------------------------------------------

  defp run(:stream_001, _ctx, u), do: stream_artifact(u, Part.text("Stream hello from TCK"))

  defp run(:stream_002, _ctx, u), do: TaskUpdater.complete(u)

  defp run(:stream_003, _ctx, u), do: stream_artifact(u, Part.text("Stream task lifecycle"))

  defp run(:stream_ordering_001, _ctx, u), do: stream_artifact(u, Part.text("Ordered output"))

  defp run(:stream_artifact_text, _ctx, u),
    do: stream_artifact(u, Part.text("Streamed text content"))

  defp run(:stream_artifact_file, _ctx, u),
    do: stream_artifact(u, Part.raw("Generated file content", @file_opts))

  defp run(:stream_artifact_chunked, _ctx, u) do
    id = "chunked-artifact"

    u
    |> TaskUpdater.start_work()
    |> TaskUpdater.add_artifact(Part.text("chunk-1 "),
      artifact_id: id,
      append: false,
      last_chunk: false
    )
    |> TaskUpdater.add_artifact(Part.text("chunk-2"),
      artifact_id: id,
      append: true,
      last_chunk: true
    )
    |> TaskUpdater.complete()
  end

  defp run(:resubscribe_long_running, _ctx, u) do
    u = TaskUpdater.start_work(u)
    Process.sleep(hold_ms())
    TaskUpdater.complete(u)
  end

  # --- default ------------------------------------------------------------

  # The feature files specify ordinary completion for unprefixed traffic; most
  # TCK tests only need *some* completed task to operate on.
  defp run(:default, ctx, u) do
    u
    |> TaskUpdater.add_artifact(Part.text("echo: " <> RequestContext.user_input(ctx)))
    |> TaskUpdater.complete(Part.text("Hello from TCK"))
  end

  # --- helpers ------------------------------------------------------------

  # working -> artifact -> completed, the shape every streaming scenario shares.
  defp stream_artifact(u, %Part{} = part) do
    u
    |> TaskUpdater.start_work()
    |> TaskUpdater.add_artifact(part)
    |> TaskUpdater.complete()
  end

  @doc """
  How long a `test-resubscribe-message-id` task must stay live, in milliseconds.

  Twice `TCK_STREAMING_TIMEOUT` (default #{@default_streaming_timeout}s), per the
  TCK's `docs/SUT_REQUIREMENTS.md`. Public so it can be exercised without
  actually sleeping for it.
  """
  @spec hold_ms() :: pos_integer()
  def hold_ms do
    round(2 * streaming_timeout() * 1000)
  end

  # `Float.parse/1` rather than `String.to_float/1`: the TCK documents values
  # like "5.0" but "2" is just as legal, and to_float/1 raises on it.
  defp streaming_timeout do
    with raw when is_binary(raw) <- System.get_env("TCK_STREAMING_TIMEOUT"),
         {timeout, _rest} <- Float.parse(raw) do
      timeout
    else
      _ -> @default_streaming_timeout
    end
  end
end
