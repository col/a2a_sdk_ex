defmodule A2A.Server.PushDispatcher do
  @moduledoc """
  One dispatcher per task that has ≥1 push config. Subscribes to the task's PubSub
  topic and, for each event, re-reads the task's configs from the `PushConfigStore`
  and delivers the event (as a `StreamResponse`) to every webhook concurrently,
  awaiting all before the next event → per-task ordering. A slow/hung consumer
  blocks only this task (bounded by `push_timeout`); other tasks are unaffected.
  Best-effort: delivery failures are logged, never raised. Shuts down after the
  task's terminal event or an idle timeout.
  """
  use GenServer, restart: :temporary
  require Logger

  alias A2A.Server.{Events, StreamFrame}
  alias A2A.Server.Events.Event

  @idle_timeout 60_000

  @spec start_link(%{server: A2A.Server.t(), task_id: String.t()}) :: GenServer.on_start()
  def start_link(%{server: server, task_id: task_id} = arg) do
    GenServer.start_link(__MODULE__, arg, name: via(server, task_id))
  end

  defp via(server, task_id), do: {:via, Registry, {server.push_registry, task_id}}

  @impl true
  def init(%{server: server, task_id: task_id}) do
    :ok = Events.subscribe(server.pubsub, task_id)
    {:ok, %{server: server, task_id: task_id}, @idle_timeout}
  end

  @impl true
  def handle_info(%Event{payload: payload, terminal?: terminal?}, state) do
    deliver(state.server, state.task_id, StreamFrame.of(payload))
    if terminal?, do: {:stop, :normal, state}, else: {:noreply, state, @idle_timeout}
  end

  def handle_info(:timeout, state), do: {:stop, :normal, state}
  def handle_info(_other, state), do: {:noreply, state, @idle_timeout}

  defp deliver(server, task_id, frame) do
    {:ok, configs} = server.push_store.list(task_id, server.scope)

    configs
    |> Task.async_stream(
      fn cfg -> dispatch_one(server, task_id, cfg, frame) end,
      max_concurrency: max(length(configs), 1),
      timeout: stream_timeout(server.push_timeout),
      on_timeout: :kill_task
    )
    |> Stream.run()
  end

  # `server.push_timeout` may be `:infinity` (a valid `timeout_opt()`); guard the
  # `+ 1_000` so an `:infinity` host config doesn't crash the dispatcher on first
  # delivery (`:infinity + 1_000` raises `ArithmeticError`).
  defp stream_timeout(:infinity), do: :infinity
  defp stream_timeout(t), do: t + 1_000

  defp dispatch_one(server, task_id, cfg, frame) do
    case server.push_sender.send(cfg, frame, timeout: server.push_timeout) do
      :ok -> :ok
      {:error, reason} -> warn(task_id, cfg, reason)
    end
  rescue
    e -> warn(task_id, cfg, e)
  catch
    kind, reason -> warn(task_id, cfg, {kind, reason})
  end

  defp warn(task_id, cfg, reason) do
    Logger.warning("push delivery failed task_id=#{task_id} url=#{cfg.url}: #{inspect(reason)}")
    :error
  end
end
