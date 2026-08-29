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

defmodule A2A.Test.BoomExecutor do
  @moduledoc "Raises, to exercise crash → failed."
  @behaviour A2A.Server.AgentExecutor
  @impl true
  def execute(_ctx, _updater), do: raise("boom")
  @impl true
  def cancel(_ctx, _updater), do: :ok
end
