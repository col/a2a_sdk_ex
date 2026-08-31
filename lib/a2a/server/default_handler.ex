defmodule A2A.Server.DefaultHandler do
  @moduledoc """
  Batteries-included `RequestHandler`. Implements the blocking `send_message/2` and
  `get_task/2` path, plus the streaming `send_message_stream/2` and `resubscribe/2`
  path. The blocking path subscribes to the task topic *before* starting the execution
  process, then folds the shared `A2A.Server.EventStream` through `ResultAssembler` to
  the terminal (or `input_required`) frame. The streaming path subscribes eagerly and
  returns a lazy `EventStream`-backed enumerable — see the enumeration contract noted
  on `send_message_stream/2` and `resubscribe/2`.
  """
  @behaviour A2A.Server.RequestHandler

  require Logger

  alias A2A.Server.{
    Events,
    EventStream,
    Execution,
    PushDispatcher,
    RequestContext,
    ResultAssembler,
    StreamFrame,
    TaskUpdater
  }

  alias A2A.Server.Events.Event

  alias A2A.Types.{
    CancelTaskRequest,
    DeleteTaskPushNotificationConfigRequest,
    GetTaskPushNotificationConfigRequest,
    GetTaskRequest,
    ListTaskPushNotificationConfigsRequest,
    ListTaskPushNotificationConfigsResponse,
    ListTasksRequest,
    ListTasksResponse,
    Message,
    SendMessageConfiguration,
    SendMessageRequest,
    StreamResponse,
    SubscribeToTaskRequest,
    Task,
    TaskPushNotificationConfig
  }

  @epoch DateTime.from_unix!(0)
  @default_page_size 50
  @max_page_size 100

  @impl true
  @spec send_message(A2A.Server.t(), SendMessageRequest.t(), keyword()) ::
          {:ok, Task.t()} | {:error, A2A.Error.t()}
  def send_message(
        %A2A.Server{} = server,
        %SendMessageRequest{message: %Message{} = message} = req,
        opts \\ []
      ) do
    task_id = message.task_id || server.id_generator.()
    context_id = message.context_id || server.id_generator.()
    timeout = Keyword.get(opts, :drain_timeout, server.drain_timeout)

    with :ok <- reject_terminal(server, task_id) do
      ctx = build_context(message, task_id, context_id, req)
      maybe_register_inline_push(server, task_id, req)
      :ok = Events.subscribe(server.pubsub, task_id)

      case start_execution(server, task_id, context_id, ctx) do
        {:ok, pid} ->
          server
          |> drain_stream(task_id, context_id, pid, timeout)
          |> then(&resolve_blocking(server, task_id, &1))

        {:error, {:already_started, _}} ->
          Events.unsubscribe(server.pubsub, task_id)
          {:error, %A2A.Error{code: :task_in_progress, message: "task already running"}}

        {:error, reason} ->
          Events.unsubscribe(server.pubsub, task_id)
          {:error, %A2A.Error{code: :internal_error, message: inspect(reason)}}
      end
    end
  end

  defp drain_stream(server, task_id, context_id, pid, timeout) do
    server.pubsub
    |> EventStream.stream(task_id, monitor: pid, idle_timeout: timeout, subscribe?: false)
    |> Enum.reduce_while({:running, ResultAssembler.init(task_id, context_id)}, &fold_event/2)
  end

  defp fold_event(%Event{payload: payload, terminal?: true}, {_, acc}),
    do: {:halt, {:done, ResultAssembler.apply(acc, payload)}}

  defp fold_event(%Event{payload: payload}, {_, acc}),
    do: {:cont, {:running, ResultAssembler.apply(acc, payload)}}

  @doc """
  Starts (or attaches to) execution and returns a lazy stream of `StreamResponse` frames.

  Enumeration contract: subscription and execution start/lookup happen eagerly, in the
  calling process, before this function returns — but the returned stream's `receive`
  runs at *enumeration* time, in whichever process enumerates it. PubSub events are
  delivered to the mailbox of the process that called `send_message_stream/2`, so the
  returned enumerable **must be enumerated exactly once, by that same process**.
  Enumerating it from a different process will miss events (they pile up in the
  original caller's mailbox instead); never enumerating it leaks the subscription
  until the calling process dies.
  """
  @impl true
  @spec send_message_stream(A2A.Server.t(), SendMessageRequest.t()) ::
          Enumerable.t() | {:error, A2A.Error.t()}
  def send_message_stream(
        %A2A.Server{} = server,
        %SendMessageRequest{message: %Message{} = message} = req
      ) do
    task_id = message.task_id || server.id_generator.()
    context_id = message.context_id || server.id_generator.()

    with :ok <- reject_terminal(server, task_id) do
      ctx = build_context(message, task_id, context_id, req)
      maybe_register_inline_push(server, task_id, req)
      :ok = Events.subscribe(server.pubsub, task_id)

      case start_execution(server, task_id, context_id, ctx) do
        {:ok, pid} ->
          server.pubsub
          |> EventStream.stream(task_id, monitor: pid, idle_timeout: :infinity, subscribe?: false)
          |> Stream.map(&StreamFrame.of(&1.payload))

        {:error, {:already_started, _}} ->
          Events.unsubscribe(server.pubsub, task_id)
          {:error, %A2A.Error{code: :task_in_progress, message: "task already running"}}

        {:error, reason} ->
          Events.unsubscribe(server.pubsub, task_id)
          {:error, %A2A.Error{code: :internal_error, message: inspect(reason)}}
      end
    end
  end

  @doc """
  Re-attaches to an in-flight (or already-settled) task and returns a lazy stream: a
  snapshot frame followed by any live frames.

  Enumeration contract: subscription and the store/registry reads happen eagerly, in
  the calling process, before this function returns — but the returned stream's
  `receive` runs at *enumeration* time, in whichever process enumerates it. PubSub
  events are delivered to the mailbox of the process that called `resubscribe/2`, so
  the returned enumerable **must be enumerated exactly once, by that same process**.
  Enumerating it from a different process will miss events (they pile up in the
  original caller's mailbox instead); never enumerating it leaks the subscription
  until the calling process dies.
  """
  @impl true
  @spec resubscribe(A2A.Server.t(), SubscribeToTaskRequest.t()) ::
          {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
  def resubscribe(%A2A.Server{} = server, %SubscribeToTaskRequest{id: task_id}) do
    # Subscribe first, then read the snapshot, so an event landing in the gap is
    # seen (via the live stream) rather than missed.
    :ok = Events.subscribe(server.pubsub, task_id)

    case server.store.get(task_id, server.scope) do
      {:error, :not_found} ->
        Events.unsubscribe(server.pubsub, task_id)
        {:error, A2A.Error.not_found(task_id)}

      {:ok, %Task{} = task} ->
        {snapshot_task, live} = resubscribe_attach(server, task_id, task)
        {:ok, Stream.concat([StreamResponse.task(snapshot_task)], live)}
    end
  end

  defp resubscribe_attach(server, task_id, task) do
    case Registry.lookup(server.registry, task_id) do
      [{pid, _}] ->
        live_stream =
          server.pubsub
          |> EventStream.stream(task_id, monitor: pid, idle_timeout: :infinity, subscribe?: false)
          |> Stream.map(&StreamFrame.of(&1.payload))

        {task, live_stream}

      [] ->
        # No live execution now — but `task` was read BEFORE this lookup, so if the
        # execution settled in that gap, Registry.lookup/2 returns `[]` (process
        # exited) while `task` is the STALE pre-terminal snapshot — and the terminal
        # event already buffered in this process's mailbox is about to be discarded
        # by unsubscribe below. Re-read the store: the process can only have exited
        # (making the lookup return `[]`) AFTER persisting its terminal state, so this
        # fresh read is terminal by construction and closes the settle-between-read-
        # and-lookup window. Fall back to the original snapshot if the fresh read
        # somehow misses (shouldn't happen — the task existed a moment ago).
        fresh_task =
          case server.store.get(task_id, server.scope) do
            {:ok, %Task{} = fresh} -> fresh
            {:error, :not_found} -> task
          end

        Events.unsubscribe(server.pubsub, task_id)
        {fresh_task, []}
    end
  end

  @impl true
  @spec get_task(A2A.Server.t(), GetTaskRequest.t()) :: {:ok, Task.t()} | {:error, A2A.Error.t()}
  def get_task(%A2A.Server{} = server, %GetTaskRequest{id: id}) do
    case server.store.get(id, server.scope) do
      {:ok, task} -> {:ok, task}
      {:error, :not_found} -> {:error, A2A.Error.not_found(id)}
    end
  end

  @impl true
  @spec cancel_task(A2A.Server.t(), CancelTaskRequest.t()) ::
          {:ok, Task.t()} | {:error, A2A.Error.t()}
  def cancel_task(%A2A.Server{} = server, %CancelTaskRequest{id: id}) do
    case Registry.lookup(server.registry, id) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :cancel)
        catch
          # Process finished in the race window (completed/stopped before we called).
          # Only "process is gone" exits fall back; a genuine call timeout (a still-
          # running cancel) or any other exit propagates rather than double-writing.
          :exit, {:noproc, _} -> cancel_not_live(server, id)
          :exit, {:normal, _} -> cancel_not_live(server, id)
        end

      [] ->
        cancel_not_live(server, id)
    end
  end

  # No live execution: terminal -> not_cancelable; non-terminal persisted -> settle
  # :canceled in the store (+ broadcast) so a late resubscriber sees it; missing ->
  # not_found.
  defp cancel_not_live(server, id) do
    case server.store.get(id, server.scope) do
      {:ok, %Task{} = task} ->
        if ResultAssembler.terminal?(task) do
          {:error, A2A.Error.not_cancelable(id)}
        else
          updater =
            TaskUpdater.new(id, task.context_id,
              pubsub: server.pubsub,
              store: server.store,
              scope: server.scope,
              task: task
            )

          updater = TaskUpdater.update_status(updater, :canceled)
          {:ok, updater.task}
        end

      {:error, :not_found} ->
        {:error, A2A.Error.not_found(id)}
    end
  end

  defp reject_terminal(server, task_id) do
    case server.store.get(task_id, server.scope) do
      {:ok, task} ->
        if ResultAssembler.terminal?(task),
          do: {:error, A2A.Error.terminal_task(task_id)},
          else: :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp build_context(message, task_id, context_id, req) do
    %RequestContext{
      message: message,
      task_id: task_id,
      context_id: context_id,
      task: nil,
      user: A2A.User.anonymous(),
      config: req.configuration || %{}
    }
  end

  defp start_execution(server, task_id, context_id, ctx) do
    arg = %{
      task_id: task_id,
      context_id: context_id,
      executor: server.executor,
      context: ctx,
      updater_opts: [pubsub: server.pubsub, store: server.store, scope: server.scope],
      registry: server.registry
    }

    Execution.start(server.dyn_sup, server.registry, arg)
  end

  # Stream ended with a terminal frame → return the assembled task.
  defp resolve_blocking(_server, _task_id, {:done, %Task{} = task}), do: {:ok, task}

  # Stream ended without a terminal frame (execution :DOWN or idle timeout).
  # A caught executor raise persists `failed`, so prefer the store's terminal task;
  # otherwise this was a genuine timeout on a still-live task.
  defp resolve_blocking(server, task_id, {:running, _partial}) do
    case server.store.get(task_id, server.scope) do
      {:ok, %Task{} = task} ->
        if ResultAssembler.terminal?(task),
          do: {:ok, task},
          else: {:error, %A2A.Error{code: :timeout, message: "timed out draining task events"}}

      {:error, :not_found} ->
        {:error, %A2A.Error{code: :timeout, message: "timed out draining task events"}}
    end
  end

  @impl true
  @spec list_tasks(A2A.Server.t(), A2A.Types.ListTasksRequest.t()) ::
          {:ok, A2A.Types.ListTasksResponse.t()} | {:error, A2A.Error.t()}
  def list_tasks(%A2A.Server{} = server, %ListTasksRequest{} = req) do
    case decode_cursor(req.page_token) do
      {:ok, cursor} -> do_list_tasks(server, req, cursor)
      {:error, %A2A.Error{}} = error -> error
    end
  end

  defp do_list_tasks(server, req, cursor) do
    filter = %{
      context_id: req.context_id,
      status: req.status,
      status_timestamp_after: req.status_timestamp_after
    }

    {:ok, all} = server.store.list(filter, server.scope)
    sorted = Enum.sort(all, &sort_desc/2)
    total = length(sorted)
    page_size = clamp_page_size(req.page_size)

    remaining = after_cursor(sorted, cursor)
    page = Enum.take(remaining, page_size)

    next =
      if length(remaining) > page_size,
        do: page |> List.last() |> cursor_of(),
        else: ""

    tasks = Enum.map(page, &post_process(&1, req))

    {:ok,
     %ListTasksResponse{
       tasks: tasks,
       next_page_token: next,
       page_size: page_size,
       total_size: total
     }}
  end

  defp clamp_page_size(nil), do: @default_page_size
  defp clamp_page_size(n) when n < 1, do: 1
  defp clamp_page_size(n) when n > @max_page_size, do: @max_page_size
  defp clamp_page_size(n), do: n

  defp ts_of(%Task{status: %{timestamp: nil}}), do: @epoch
  defp ts_of(%Task{status: %{timestamp: ts}}), do: ts

  # descending timestamp, ascending id tiebreak
  defp sort_desc(a, b) do
    case DateTime.compare(ts_of(a), ts_of(b)) do
      :gt -> true
      :lt -> false
      :eq -> a.id <= b.id
    end
  end

  defp after_cursor(sorted, nil), do: sorted

  defp after_cursor(sorted, {c_ts, c_id}) do
    Enum.filter(sorted, fn t ->
      case DateTime.compare(ts_of(t), c_ts) do
        :lt -> true
        :gt -> false
        :eq -> t.id > c_id
      end
    end)
  end

  defp cursor_of(%Task{} = t),
    do: Base.url_encode64("#{DateTime.to_iso8601(ts_of(t))}|#{t.id}")

  defp decode_cursor(nil), do: {:ok, nil}
  defp decode_cursor(""), do: {:ok, nil}

  defp decode_cursor(token) do
    with {:ok, raw} <- Base.url_decode64(token),
         [iso, id] <- String.split(raw, "|", parts: 2),
         {:ok, ts, _} <- DateTime.from_iso8601(iso) do
      {:ok, {ts, id}}
    else
      _ -> {:error, %A2A.Error{code: :invalid_params, message: "invalid page_token"}}
    end
  end

  defp post_process(%Task{} = task, %ListTasksRequest{} = req) do
    task
    |> truncate_history(req.history_length)
    |> maybe_drop_artifacts(req.include_artifacts)
  end

  defp truncate_history(task, nil), do: task
  defp truncate_history(task, n) when n < 0, do: task

  defp truncate_history(task, n),
    do: %{task | history: Enum.take(task.history, -n)}

  defp maybe_drop_artifacts(task, true), do: task
  defp maybe_drop_artifacts(task, _), do: %{task | artifacts: []}

  # --- push notification config ops ---

  @impl true
  def create_push_config(%A2A.Server{} = server, %TaskPushNotificationConfig{} = config) do
    with :ok <- ensure_push_enabled(server),
         :ok <- ensure_task_id(config.task_id),
         :ok <- validate_url(server, config.url) do
      stored = %{config | id: config.id || server.id_generator.()}
      :ok = server.push_store.put(stored, server.scope)
      ensure_dispatcher(server, stored.task_id)
      {:ok, stored}
    end
  end

  @impl true
  def get_push_config(%A2A.Server{} = server, %GetTaskPushNotificationConfigRequest{
        task_id: task_id,
        id: id
      }) do
    with :ok <- ensure_push_enabled(server) do
      case server.push_store.get(task_id, id, server.scope) do
        {:ok, config} -> {:ok, config}
        {:error, :not_found} -> {:error, A2A.Error.not_found(task_id)}
      end
    end
  end

  @impl true
  def list_push_configs(%A2A.Server{} = server, %ListTaskPushNotificationConfigsRequest{
        task_id: task_id
      }) do
    with :ok <- ensure_push_enabled(server) do
      {:ok, configs} = server.push_store.list(task_id, server.scope)
      {:ok, %ListTaskPushNotificationConfigsResponse{configs: configs, next_page_token: ""}}
    end
  end

  @impl true
  def delete_push_config(%A2A.Server{} = server, %DeleteTaskPushNotificationConfigRequest{
        task_id: task_id,
        id: id
      }) do
    with :ok <- ensure_push_enabled(server) do
      :ok = server.push_store.delete(task_id, id, server.scope)
      {:ok, :deleted}
    end
  end

  defp maybe_register_inline_push(%A2A.Server{push_notifications: true} = server, task_id, %{
         configuration: %SendMessageConfiguration{
           task_push_notification_config: %TaskPushNotificationConfig{} = cfg
         }
       }) do
    stored = %{cfg | task_id: task_id, id: cfg.id || server.id_generator.()}

    case validate_url(server, stored.url) do
      :ok ->
        best_effort_put(server, stored)
        ensure_dispatcher(server, task_id)
        :ok

      {:error, _} ->
        # Best-effort: an invalid inline webhook URL is ignored rather than
        # failing the whole SendMessage. The config CRUD path validates strictly.
        :ok
    end
  end

  defp maybe_register_inline_push(_server, _task_id, _req), do: :ok

  # Best-effort store write for the INLINE registration path only: a custom
  # `push_store.put/2` that raises, exits, or returns something other than `:ok`
  # must not fail `SendMessage` (the config CRUD path, `create_push_config/2`,
  # deliberately lets a store failure surface — this helper is inline-only).
  defp best_effort_put(server, stored) do
    case server.push_store.put(stored, server.scope) do
      :ok ->
        :ok

      other ->
        Logger.warning(
          "inline push config store failed task_id=#{stored.task_id}: #{inspect(other)}"
        )

        :ok
    end
  rescue
    e ->
      Logger.warning("inline push config store raised task_id=#{stored.task_id}: #{inspect(e)}")
      :ok
  catch
    kind, reason ->
      Logger.warning(
        "inline push config store #{kind} task_id=#{stored.task_id}: #{inspect(reason)}"
      )

      :ok
  end

  # Best-effort dispatcher start: a failure to start the delivery process must not
  # fail config creation (config is persisted) nor the SendMessage (inline path).
  defp ensure_dispatcher(server, task_id) do
    case PushDispatcher.Supervisor.ensure_started(server, task_id) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.warning("push dispatcher start failed task_id=#{task_id}: #{inspect(reason)}")
        :ok
    end
  end

  defp ensure_push_enabled(%A2A.Server{push_notifications: true, push_store: store})
       when not is_nil(store),
       do: :ok

  defp ensure_push_enabled(_server),
    do:
      {:error,
       %A2A.Error{
         code: :push_notification_not_supported,
         message: "push notifications are not supported by this agent"
       }}

  defp ensure_task_id(task_id) when is_binary(task_id) and task_id != "", do: :ok

  defp ensure_task_id(_),
    do: {:error, %A2A.Error{code: :invalid_params, message: "task_id is required"}}

  defp validate_url(%A2A.Server{push_url_validator: nil}, _url), do: :ok

  defp validate_url(%A2A.Server{push_url_validator: v}, url) do
    case v.(url) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %A2A.Error{code: :invalid_params, message: "invalid webhook url: #{inspect(reason)}"}}
    end
  end
end
