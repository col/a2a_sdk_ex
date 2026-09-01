defmodule A2A.Server.Agent.Interpreter do
  @moduledoc """
  Folds an `A2A.Server.Agent.Result` into `A2A.Server.TaskUpdater` calls: signal
  work, emit each artifact directive in author order (streams as chunk-merged
  appends), then settle the terminal. Runs inside the execution child process, so
  a stream that raises mid-enumeration surfaces as the normal task-fail path.
  """
  alias A2A.Server.Agent.Result
  alias A2A.Server.TaskUpdater
  alias A2A.Types.{Artifact, Message, Part}

  @spec run(Result.t(), TaskUpdater.t()) :: :ok
  def run(%Result{} = result, %TaskUpdater{} = updater) do
    updater
    |> TaskUpdater.start_work()
    |> emit_directives(Result.directives(result))
    |> settle(result)

    :ok
  end

  defp emit_directives(updater, directives), do: Enum.reduce(directives, updater, &emit/2)

  defp emit({:artifact, name, parts, opts}, updater) do
    artifact = %Artifact{
      artifact_id: Keyword.get(opts, :id, gen_id()),
      name: name,
      parts: parts,
      metadata: Keyword.get(opts, :metadata)
    }

    TaskUpdater.add_artifact(updater, artifact, append: false, last_chunk: true)
  end

  defp emit({:stream, name, enumerable, opts}, updater) do
    id = Keyword.get(opts, :id, gen_id())
    meta = Keyword.get(opts, :metadata)

    {updater, pending} =
      Enum.reduce(enumerable, {updater, :none}, fn element, {updater, pending} ->
        case pending do
          :none -> {updater, {element}}
          {prev} -> {chunk(updater, id, name, meta, [normalize(prev)], false), {element}}
        end
      end)

    case pending do
      :none -> chunk(updater, id, name, meta, [], true)
      {last} -> chunk(updater, id, name, meta, [normalize(last)], true)
    end
  end

  defp chunk(updater, id, name, meta, parts, last?) do
    artifact = %Artifact{artifact_id: id, name: name, parts: parts, metadata: meta}
    TaskUpdater.add_artifact(updater, artifact, append: true, last_chunk: last?)
  end

  defp settle(updater, %Result{terminal: terminal, message: message}) do
    {state, _opts} = terminal || {:completed, []}
    TaskUpdater.update_status(updater, state, build_message(updater, message))
  end

  defp build_message(_updater, nil), do: nil

  defp build_message(updater, {parts, opts}) do
    %Message{
      message_id: gen_id(),
      role: :agent,
      task_id: updater.task_id,
      context_id: updater.context_id,
      parts: parts,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  defp normalize(s) when is_binary(s), do: Part.text(s)
  defp normalize(%Part{} = p), do: p

  defp gen_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
