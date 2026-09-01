defmodule A2A.Test.Wait do
  @moduledoc """
  Test-only synchronisation helpers.

  A blocking `send_message/2` returns on the terminal-or-interrupted *event*, a
  moment before that turn's execution process actually exits. `Registry` keys are
  unique per task id, so a second turn started in that window is rejected as
  `:task_in_progress` — tests that start one wait here first.
  """
  import ExUnit.Assertions

  @spec for_no_execution(A2A.Server.t(), String.t(), non_neg_integer()) :: :ok
  def for_no_execution(server, task_id, tries \\ 50) do
    case Registry.lookup(server.registry, task_id) do
      [] ->
        :ok

      _ when tries > 0 ->
        Process.sleep(20)
        for_no_execution(server, task_id, tries - 1)

      _ ->
        flunk("execution for #{task_id} never exited")
    end
  end
end
