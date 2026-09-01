defmodule A2A.Server.DefaultHandler do
  @moduledoc """
  The batteries-included `A2A.Server.RequestHandler`, wired up automatically by
  `A2A.Server.Supervisor` — you don't call it directly unless you're driving the
  server from plain Elixir. It implements the blocking `send_message/2` and
  `get_task/2` path, the streaming `send_message_stream/2` and `resubscribe/2`
  path, `cancel_task/2`, `list_tasks/2`, and the push-notification-config
  callbacks.

  `send_message_stream/2` and `resubscribe/2` return a lazy, PubSub-backed
  enumerable that must be enumerated in the process that requested it — the
  subscription is opened eagerly on the calling process before the function
  returns.
  """
  @behaviour A2A.Server.RequestHandler

  require Logger

  alias A2A.Server.{
    BlockingDrain,
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
    TaskPushNotificationConfig,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  @epoch DateTime.from_unix!(0)
  @default_page_size 50
  @max_page_size 100

  @impl true
  @spec send_message(A2A.Server.t(), SendMessageRequest.t(), keyword()) ::
          {:ok, Task.t() | Message.t()} | {:error, A2A.Error.t()}
  def send_message(server, req, opts \\ [])

  def send_message(
        %A2A.Server{} = server,
        %SendMessageRequest{message: %Message{} = message} = req,
        opts
      ) do
    timeout = Keyword.get(opts, :drain_timeout, server.drain_timeout)

    with {:ok, existing} <- resolve_task(server, message) do
      task_id = message.task_id || server.id_generator.()
      context_id = context_id_for(existing, message, server)
      seed = seed_task(existing, task_id, context_id, message)
      ctx = build_context(message, task_id, context_id, req)
      maybe_register_inline_push(server, task_id, req)
      ensure_dispatcher_for_configured(server, task_id)

      case drain_blocking(server, task_id, context_id, ctx, seed, timeout) do
        {:ok, drained} ->
          drained
          |> then(&resolve_blocking(server, task_id, &1))
          |> then(&truncate_result(&1, req))

        {:error, {:already_started, _}} ->
          {:error, %A2A.Error{code: :task_in_progress, message: "task already running"}}

        {:error, reason} ->
          {:error, %A2A.Error{code: :internal_error, message: inspect(reason)}}
      end
    end
  end

  def send_message(%A2A.Server{}, %SendMessageRequest{message: nil}, _opts),
    do: {:error, missing_message()}

  # `SendMessageRequest.message` is required by the spec, but proto3-JSON has no
  # notion of a required field: an absent `message` decodes to nil. Both bindings
  # land here, so rejecting it at the handler covers JSON-RPC and REST alike.
  defp missing_message,
    do: %A2A.Error{code: :invalid_params, message: "SendMessageRequest.message is required"}

  # The drain runs in its OWN process (`A2A.Server.BlockingDrain`), which subscribes,
  # hands back a `:ready` handshake so the execution still starts strictly after the
  # subscription, folds, reports, and exits. Because §3.2.2 lets the fold stop while
  # the executor keeps emitting, anything broadcast after the halt must land in a
  # mailbox nobody reads again — a process that dies is the only way to guarantee it
  # is never mistaken for the caller's next operation.
  defp drain_blocking(server, task_id, context_id, ctx, seed, timeout) do
    BlockingDrain.run(
      pubsub: server.pubsub,
      task_id: task_id,
      seed: {:running, seed},
      idle_timeout: timeout,
      start: fn -> start_execution(server, task_id, context_id, ctx, seed) end,
      fold: &fold_event/2
    )
  end

  # A bare `Message` payload is a direct reply (spec 3.1.1): no task was created,
  # so it is returned as-is rather than folded into one. Nothing else ever
  # broadcasts a `Message` — history seeding applies it to the projection
  # directly, never through the event stream.
  defp fold_event(%Event{payload: %Message{} = message}, _acc),
    do: {:halt, {:message, message}}

  defp fold_event(%Event{payload: payload}, {_, acc}) do
    task = ResultAssembler.apply(acc, payload)

    if Events.final?(payload) or interrupted?(payload),
      do: {:halt, {:done, task}},
      else: {:cont, {:running, task}}
  end

  # Spec §3.2.2: a blocking send returns when the task reaches a terminal state OR
  # an interrupted state (`input_required`, `auth_required`) — the execution stays
  # alive and the task resumable; only the caller's wait ends. Streams deliberately
  # do NOT stop here (§3.1.2, §3.1.6), which is why this rule lives in the handler
  # rather than in `A2A.Server.EventStream`.
  defp interrupted?(%TaskStatusUpdateEvent{status: %TaskStatus{state: state}}),
    do: state in [:input_required, :auth_required]

  defp interrupted?(_payload), do: false

  @doc """
  Starts (or attaches to) execution and returns a lazy stream of `StreamResponse` frames.

  The stream closes when the task reaches a **terminal** state (§3.1.2) or after a
  direct `Message` reply — not when a turn ends. An agent that parks at
  `input_required` keeps the stream open: the client answers on a separate request
  and the next turn's frames arrive here. `server.stream_idle_timeout` bounds a
  stream that goes completely silent.

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
    with {:ok, existing} <- resolve_task(server, message) do
      task_id = message.task_id || server.id_generator.()
      context_id = context_id_for(existing, message, server)
      seed = seed_task(existing, task_id, context_id, message)
      ctx = build_context(message, task_id, context_id, req)
      maybe_register_inline_push(server, task_id, req)
      ensure_dispatcher_for_configured(server, task_id)
      :ok = Events.subscribe(server.pubsub, task_id)

      case start_execution(server, task_id, context_id, ctx, seed) do
        {:ok, _pid} ->
          server.pubsub
          |> EventStream.stream(task_id,
            idle_timeout: server.stream_idle_timeout,
            subscribe?: false
          )
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

  def send_message_stream(%A2A.Server{}, %SendMessageRequest{message: nil}),
    do: {:error, missing_message()}

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
        subscribe_live(server, task_id, task)
    end
  end

  # No execution lookup: the PubSub topic is keyed by task id and outlives any
  # single turn, so a task parked between turns gets a live stream like any other.
  # Subscribing BEFORE the store read (in `resubscribe/2`) also closes the old
  # settle-in-the-gap window — a task that terminates after the snapshot delivers
  # its terminal event on this stream instead of being dropped by an unsubscribe.
  #
  # Spec 3.1.6: SubscribeToTask "returns UnsupportedOperationError if the task is
  # in a terminal state". A snapshot-only stream is not a substitute — the
  # subscriber cannot distinguish it from a task that is merely quiet.
  defp subscribe_live(server, task_id, %Task{} = task) do
    case ResultAssembler.terminal?(task) do
      true ->
        Events.unsubscribe(server.pubsub, task_id)

        {:error,
         %A2A.Error{
           code: :unsupported_operation,
           message: "task is in a terminal state and cannot be subscribed to: #{task_id}",
           data: %{task_id: task_id}
         }}

      false ->
        live =
          server.pubsub
          |> EventStream.stream(task_id,
            idle_timeout: server.stream_idle_timeout,
            subscribe?: false
          )
          |> Stream.map(&StreamFrame.of(&1.payload))

        {:ok, Stream.concat([StreamResponse.task(task)], live)}
    end
  end

  @impl true
  @spec get_task(A2A.Server.t(), GetTaskRequest.t()) :: {:ok, Task.t()} | {:error, A2A.Error.t()}
  def get_task(%A2A.Server{} = server, %GetTaskRequest{id: id} = req) do
    case server.store.get(id, server.scope) do
      {:ok, task} -> {:ok, truncate_history(task, req.history_length)}
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

          ensure_dispatcher_for_configured(server, id)
          updater = TaskUpdater.update_status(updater, :canceled)
          {:ok, updater.task}
        end

      {:error, :not_found} ->
        {:error, A2A.Error.not_found(id)}
    end
  end

  # Spec 3.4.2: task ids are server-generated, and "client-provided taskId values
  # for creating new tasks is NOT supported". So an absent taskId means "create"
  # (`{:ok, nil}`), and a supplied one MUST reference an existing, non-terminal
  # task — an unknown id is TaskNotFound rather than an implicit create. The task
  # itself is returned so the caller can continue it rather than start over.
  defp resolve_task(_server, %Message{task_id: nil}), do: {:ok, nil}

  defp resolve_task(server, %Message{task_id: task_id} = message) do
    case server.store.get(task_id, server.scope) do
      {:ok, task} ->
        cond do
          ResultAssembler.terminal?(task) -> {:error, A2A.Error.terminal_task(task_id)}
          context_mismatch?(task, message) -> {:error, context_mismatch(task, message)}
          true -> {:ok, task}
        end

      {:error, :not_found} ->
        {:error, A2A.Error.not_found(task_id)}
    end
  end

  # Spec 3.4.3: "Agents MUST reject messages containing mismatching contextId and
  # taskId". A client that states no contextId is not mismatching — that is the
  # inference case below.
  defp context_mismatch?(%Task{context_id: actual}, %Message{context_id: stated}),
    do: is_binary(stated) and stated != "" and stated != actual

  defp context_mismatch(%Task{} = task, %Message{} = message) do
    %A2A.Error{
      code: :invalid_params,
      message: "contextId does not match the referenced task",
      data: %{task_id: task.id, context_id: task.context_id, stated: message.context_id}
    }
  end

  # Spec 3.4.3: "Agents MUST infer contextId from the task if only taskId is
  # provided". A new task takes the client's contextId, or a generated one.
  defp context_id_for(%Task{context_id: context_id}, _message, _server), do: context_id

  defp context_id_for(nil, %Message{context_id: context_id}, server),
    do: context_id || server.id_generator.()

  # The projection each turn starts from: the stored task when continuing, a fresh
  # one otherwise — with the incoming message appended so the exchange, not just
  # the agent's replies, accumulates in history (spec 3.2.4).
  defp seed_task(existing, task_id, context_id, %Message{} = message) do
    (existing || ResultAssembler.init(task_id, context_id))
    |> ResultAssembler.apply(message)
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

  defp start_execution(server, task_id, context_id, ctx, seed) do
    arg = %{
      task_id: task_id,
      context_id: context_id,
      executor: server.executor,
      context: ctx,
      updater_opts: [
        pubsub: server.pubsub,
        store: server.store,
        scope: server.scope,
        task: seed
      ],
      registry: server.registry
    }

    Execution.start(server.dyn_sup, server.registry, arg)
  end

  # Stream ended with a terminal frame → return the assembled task.
  defp resolve_blocking(_server, _task_id, {:done, %Task{} = task}), do: {:ok, task}

  # The agent answered directly; there is no task to assemble or read back.
  defp resolve_blocking(_server, _task_id, {:message, %Message{} = message}), do: {:ok, message}

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

  # Spec 3.2.4: `historyLength` caps the history in the *response*; the stored
  # task is untouched. A negative value is meaningless, so it is ignored rather
  # than inverted by `Enum.take/2`'s negative-count semantics.
  defp truncate_history(task, nil), do: task
  defp truncate_history(task, n) when n < 0, do: task

  defp truncate_history(task, n),
    do: %{task | history: Enum.take(task.history, -n)}

  defp truncate_result({:ok, %Task{} = task}, %SendMessageRequest{configuration: config}),
    do: {:ok, truncate_history(task, config && config.history_length)}

  defp truncate_result(other, _req), do: other

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

  # A dispatcher is reaped after `push_idle_timeout` of silence on an unworked task,
  # so by the time a later turn (or a cancel) broadcasts, there may be no subscriber
  # left even though the config is still registered and the client still believes it
  # is subscribed. Revive one before anything is broadcast. `ensure_started/2`
  # subscribes synchronously inside `init/1`, so calling this BEFORE the execution
  # starts is what guarantees the subscription is live for the turn's first event.
  # Costs one store read per send on a push-enabled server, and nothing at all when
  # push is off or the task has no webhooks.
  defp ensure_dispatcher_for_configured(%A2A.Server{push_notifications: true} = server, task_id) do
    case server.push_store.list(task_id, server.scope) do
      {:ok, [_ | _]} -> ensure_dispatcher(server, task_id)
      _ -> :ok
    end
  rescue
    # This read sits on the hot path of every send once push is enabled, so a host
    # store that raises must cost push delivery, not the whole SendMessage — the
    # same best-effort contract `best_effort_put/2` gives the inline path.
    e ->
      Logger.warning("push dispatcher revival failed task_id=#{task_id}: #{inspect(e)}")
      :ok
  end

  defp ensure_dispatcher_for_configured(%A2A.Server{}, _task_id), do: :ok

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
