defmodule A2A.Test.EchoExecutor do
  @moduledoc "Echoes the user's input back as a completed task."
  @behaviour A2A.Server.AgentExecutor
  alias A2A.Server.{RequestContext, TaskUpdater}
  alias A2A.Types.Part

  @impl true
  def execute(%RequestContext{} = ctx, updater) do
    text = RequestContext.user_input(ctx)

    updater
    |> TaskUpdater.start_work()
    |> TaskUpdater.add_artifact(Part.text("echo: " <> text))
    |> TaskUpdater.complete(Part.text("done"))

    :ok
  end

  @impl true
  def cancel(_ctx, updater),
    do:
      (
        TaskUpdater.update_status(updater, :canceled)
        :ok
      )
end

defmodule A2A.Test.SilentExecutor do
  @moduledoc "Emits nothing and blocks, to exercise the idle drain timeout."
  @behaviour A2A.Server.AgentExecutor
  @impl true
  def execute(_ctx, _updater), do: Process.sleep(:infinity)
  @impl true
  def cancel(_ctx, _updater), do: :ok
end

defmodule A2A.Test.AuthThenInputExecutor do
  @moduledoc "Emits auth_required (non-terminal) then input_required (stops the stream)."
  @behaviour A2A.Server.AgentExecutor
  alias A2A.Server.TaskUpdater

  @impl true
  def execute(_ctx, updater) do
    updater
    |> TaskUpdater.start_work()
    |> TaskUpdater.update_status(:auth_required)
    |> TaskUpdater.requires_input()

    :ok
  end

  @impl true
  def cancel(_ctx, _updater), do: :ok
end

defmodule A2A.Test.BoomExecutor do
  @moduledoc "Raises, to exercise crash → failed."
  @behaviour A2A.Server.AgentExecutor
  @impl true
  def execute(_ctx, _updater), do: raise("boom")
  @impl true
  def cancel(_ctx, _updater), do: :ok
end

defmodule A2A.Test.ThrowExecutor do
  @moduledoc "Throws, to exercise the catch :throw boundary → failed."
  @behaviour A2A.Server.AgentExecutor
  @impl true
  def execute(_ctx, _updater), do: throw(:boom)
  @impl true
  def cancel(_ctx, _updater), do: :ok
end

defmodule A2A.Test.ExitExecutor do
  @moduledoc "Exits abnormally, to exercise the catch :exit boundary → failed."
  @behaviour A2A.Server.AgentExecutor
  @impl true
  def execute(_ctx, _updater), do: exit(:boom)
  @impl true
  def cancel(_ctx, _updater), do: :ok
end

defmodule A2A.Test.GatedExecutor do
  @moduledoc "Starts work, blocks until `release/1`, then completes. For resubscribe tests."
  @behaviour A2A.Server.AgentExecutor
  alias A2A.Server.TaskUpdater
  alias A2A.Types.Part

  def release(task_id), do: send_to_gate(task_id, :release)

  @impl true
  def execute(ctx, updater) do
    updater = TaskUpdater.start_work(updater)
    register_gate(ctx.task_id)

    receive do
      :release -> :ok
    after
      5_000 -> :ok
    end

    TaskUpdater.complete(updater, Part.text("done"))
    :ok
  end

  @impl true
  def cancel(_ctx, _updater), do: :ok

  # Minimal gate: register the executing pid under the task id in :persistent_term.
  defp register_gate(task_id), do: :persistent_term.put({__MODULE__, task_id}, self())

  defp send_to_gate(task_id, msg) do
    case :persistent_term.get({__MODULE__, task_id}, nil) do
      pid when is_pid(pid) -> send(pid, msg)
      _ -> :ok
    end
  end
end
