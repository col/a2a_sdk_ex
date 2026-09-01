defmodule A2A.Server.EventStream do
  @moduledoc false
  alias A2A.Server.Events
  alias A2A.Server.Events.Event

  @spec stream(atom(), String.t(), keyword()) :: Enumerable.t()
  def stream(pubsub, task_id, opts \\ []) do
    idle_timeout = Keyword.get(opts, :idle_timeout, :infinity)
    monitor_pid = Keyword.get(opts, :monitor)
    subscribe? = Keyword.get(opts, :subscribe?, true)

    Stream.resource(
      fn -> start(pubsub, task_id, monitor_pid, subscribe?) end,
      fn acc -> next(acc, task_id, idle_timeout) end,
      fn acc -> stop(pubsub, task_id, acc) end
    )
  end

  defp start(pubsub, task_id, monitor_pid, subscribe?) do
    if subscribe?, do: :ok = Events.subscribe(pubsub, task_id)
    ref = if is_pid(monitor_pid), do: Process.monitor(monitor_pid), else: nil
    %{ref: ref, halted?: false}
  end

  # After a terminal event was yielded, the next pull halts.
  defp next(%{halted?: true} = acc, _task_id, _timeout), do: {:halt, acc}

  defp next(%{ref: ref} = acc, task_id, timeout) do
    receive do
      %Event{task_id: ^task_id, payload: payload} = e ->
        if Events.final?(payload),
          do: {[e], %{acc | halted?: true}},
          else: {[e], acc}

      {:DOWN, ^ref, :process, _pid, _reason} ->
        {:halt, acc}
    after
      timeout -> {:halt, acc}
    end
  end

  defp stop(pubsub, task_id, %{ref: ref}) do
    Events.unsubscribe(pubsub, task_id)
    if ref, do: Process.demonitor(ref, [:flush])
    :ok
  end
end
