defmodule A2A.Server.BlockingDrain do
  @moduledoc """
  Runs the blocking `SendMessage` drain (spec §3.2.2) in its own short-lived,
  monitored process, so the subscription and the events it collects are scoped to a
  process that dies the moment the drain is over.

  ## Why a separate process

  §3.2.2 ends a blocking wait at a terminal state **or** an interrupted state
  (`input_required`, `auth_required`), while §3.1.2/§3.1.6 keep the *task* running.
  So the drain routinely stops reading while the executor is still emitting: every
  event broadcast after the fold halts arrives in a mailbox nobody will read again.
  Unsubscribing cannot prevent that — a broadcaster that already read the subscriber
  list sends after the unsubscribe — and flushing afterwards cannot be made correct
  against a still-running executor for the same reason. Owning the subscription in a
  process that exits is the only version with no window at all: whatever the executor
  emits next is delivered to a dead process and dropped by the runtime.

  ## The handshake

  The one guarantee the old in-caller code bought by subscribing inline was
  *subscribe happens-before `start_execution`*, so no early event could fall in the
  gap. Spawning and immediately starting the execution would give that up, so the
  caller blocks on an explicit handshake instead:

      caller                          drain
        spawn_monitor ─────────────▶  subscribe(task topic)
        receive {:ready, pid}  ◀────  send {:ready, self()}
        start_execution/5
        send {:execute, pid} ──────▶  fold EventStream → result
        receive {:drained, …}  ◀────  send {:drained, self(), result}; exit

  `Events.subscribe/2` returns only once the registration is visible to any later
  broadcaster, and the drain's send of `:ready` is ordered after it; the caller's
  receive of `:ready` is ordered after that send, and `start_execution/5` after the
  receive. The subscription is therefore established before the execution process
  exists — the window is closed, not narrowed.

  A start that fails gets `{:abort, reason}` instead of `{:execute, pid}`, so the
  drain unsubscribes and exits rather than waiting for events that will never come.

  The drain's own lifetime is bounded by the two signals it hands `EventStream`: the
  monitored execution's `:DOWN` (the blocking path is the only consumer that passes
  `:monitor`) and the idle timeout. While it is still waiting for `{:execute, …}` it
  additionally watches the caller, which is the only wait not otherwise bounded.
  """
  alias A2A.Server.{Events, EventStream}
  alias A2A.Server.Events.Event

  @type acc :: term()
  @type fold :: (Event.t(), acc() -> {:cont, acc()} | {:halt, acc()})

  @doc """
  Subscribes (in a child process), starts the execution, and folds the task's events.

  Options — all required:

    * `:pubsub` / `:task_id` — the topic to drain
    * `:seed` — the fold's initial accumulator, also the result reported if the drain
      process dies without answering
    * `:idle_timeout` — `EventStream`'s idle timeout (`drain_timeout`, may be `:infinity`)
    * `:start` — zero-arity fun starting the execution; `{:ok, pid} | {:error, reason}`
    * `:fold` — the `Enum.reduce_while/3` reducer (the handler's §3.2.2 rule)

  Returns `{:ok, fold_result}`, or `{:error, reason}` verbatim from `:start` so the
  caller keeps rendering `{:already_started, _}` and other failures as it always has.
  """
  @spec run(keyword()) :: {:ok, acc()} | {:error, term()}
  def run(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    task_id = Keyword.fetch!(opts, :task_id)
    seed = Keyword.fetch!(opts, :seed)
    idle_timeout = Keyword.fetch!(opts, :idle_timeout)
    start = Keyword.fetch!(opts, :start)
    fold = Keyword.fetch!(opts, :fold)

    caller = self()

    {pid, ref} =
      spawn_monitor(fn -> drain(caller, pubsub, task_id, seed, idle_timeout, fold) end)

    receive do
      {:ready, ^pid} ->
        after_ready(pid, ref, seed, start)

      {:DOWN, ^ref, :process, ^pid, reason} ->
        # The drain could not even subscribe. Nothing was started, so there is no
        # execution to reconcile against — surface it like any other start failure.
        {:error, {:drain_exited, reason}}
    end
  end

  defp after_ready(pid, ref, seed, start) do
    case start.() do
      {:ok, exec_pid} ->
        send(pid, {:execute, exec_pid})
        await(pid, ref, seed)

      {:error, _reason} = error ->
        send(pid, {:abort, error})
        Process.demonitor(ref, [:flush])
        error
    end
  end

  defp await(pid, ref, seed) do
    receive do
      {:drained, ^pid, result} ->
        # `{:drained, …}` is sent before the drain returns, so it always precedes the
        # `:DOWN` in the mailbox and wins this selective receive.
        Process.demonitor(ref, [:flush])
        {:ok, result}

      {:DOWN, ^ref, :process, ^pid, _reason} ->
        # The drain died without answering. Report the untouched seed: that is the
        # same "ended without a terminal frame" shape an idle timeout produces, so
        # `resolve_blocking/3` re-reads the store and decides, unchanged.
        {:ok, seed}
    end
  end

  # Runs in the drain process.
  defp drain(caller, pubsub, task_id, seed, idle_timeout, fold) do
    caller_ref = Process.monitor(caller)
    :ok = Events.subscribe(pubsub, task_id)
    send(caller, {:ready, self()})

    # Selective receive: `%Event{}` envelopes that arrive in this window match none
    # of these patterns and stay queued for the fold below.
    receive do
      {:execute, exec_pid} ->
        Process.demonitor(caller_ref, [:flush])
        result = fold_events(pubsub, task_id, seed, idle_timeout, exec_pid, fold)
        send(caller, {:drained, self(), result})

      {:abort, _reason} ->
        Process.demonitor(caller_ref, [:flush])
        Events.unsubscribe(pubsub, task_id)

      {:DOWN, ^caller_ref, :process, ^caller, _reason} ->
        Events.unsubscribe(pubsub, task_id)
    end
  end

  # The fold folds into its own projection, starting from the same seed the execution
  # did — otherwise the task returned to a blocking caller would be missing the
  # history and artifacts of every earlier turn.
  defp fold_events(pubsub, task_id, seed, idle_timeout, exec_pid, fold) do
    pubsub
    |> EventStream.stream(task_id,
      monitor: exec_pid,
      idle_timeout: idle_timeout,
      subscribe?: false
    )
    |> Enum.reduce_while(seed, fold)
  end
end
