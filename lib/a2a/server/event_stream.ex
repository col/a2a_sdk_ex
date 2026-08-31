defmodule A2A.Server.EventStream do
  @moduledoc """
  Shared subscription-backed event stream for a single task, used by both the
  blocking and streaming delivery paths. A `Stream.resource/3` that subscribes to
  the task topic on start, yields each `%A2A.Server.Events.Event{}` envelope in
  publish order, and terminates on the union of three signals (see ADR-0009):

    1. a **final** event — one whose payload closes a stream per
       `A2A.Server.Events.final?/1`: a terminal task state (§3.1.2, §3.1.6) or a
       direct `Message` reply. Interrupted states (`input_required`,
       `auth_required`) do NOT end the stream; the blocking caller's own fold
       stops on those (§3.2.2);
    2. the monitored execution process going `:DOWN` — opt-in via `:monitor`, and
       passed only by the blocking drain (a stream outlives any single turn);
    3. an idle timeout (`:infinity` disables it; defense-in-depth for a silent hang).

  It always unsubscribes on halt and demonitors if it monitored. Yields the
  **domain** envelope — no wire types here; the `StreamResponse` projection lives
  in the streaming consumer.

  The `receive` **pins the task id**. A subscription is owned by a process mailbox,
  not by a stream, and one process can legitimately hold more than one at a time (a
  resubscribe stream plus a send, say) — so an envelope for another task must be
  left in the mailbox for whoever it belongs to, not folded in here. Without the pin
  a foreign terminal event both leaks its frames onto this stream and closes it.
  """
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
